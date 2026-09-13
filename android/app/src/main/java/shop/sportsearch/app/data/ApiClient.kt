package shop.sportsearch.app.data

import android.content.Context
import android.util.Log
import android.content.SharedPreferences
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.serializer
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import shop.sportsearch.app.BuildConfig
import shop.sportsearch.app.core.LocaleStore
import shop.sportsearch.app.core.RealtimeEvent
import java.io.IOException
import java.util.UUID
import java.util.concurrent.TimeUnit

/** Port of `enum APIError` in ios/TennisSearchIOS/Services/APIClient.swift. */
sealed class ApiException(message: String) : Exception(message) {
    object InvalidBaseUrl : ApiException("Не указан API base URL") {
        private fun readResolve(): Any = InvalidBaseUrl
    }

    object InvalidResponse : ApiException("Некорректный ответ сервера") {
        private fun readResolve(): Any = InvalidResponse
    }

    class Server(val rawMessage: String) : ApiException(sanitizedServerMessage(rawMessage)) {
        val isInternalServerMessage: Boolean get() = isInternalServerMessage(rawMessage)
    }

    class InvalidPayload(message: String) : ApiException(message)

    companion object {
        private const val GENERIC_SERVER_MESSAGE =
            "Сервис временно отвечает нестабильно. Попробуй ещё раз через пару секунд."

        private val INTERNAL_MARKERS = listOf(
            "<!doctype", "<html", "text/html", "body:",
            "http 500", "http 502", "http 503", "http 504",
            "prisma.", "prismaclient", "invalid `prisma",
            "unique constraint failed", "foreign key constraint", "constraint failed",
            "next-hide-fouc", "stack trace",
        )

        fun sanitizedServerMessage(message: String): String {
            val trimmed = message.trim()
            if (trimmed.isEmpty()) return GENERIC_SERVER_MESSAGE
            return if (isInternalServerMessage(trimmed)) GENERIC_SERVER_MESSAGE else trimmed
        }

        fun isInternalServerMessage(message: String): Boolean {
            val normalized = message.trim().lowercase()
            if (normalized.isEmpty()) return true
            return INTERNAL_MARKERS.any { normalized.contains(it) }
        }
    }
}

/**
 * Port of `final class APIClient`. Same base URL, same headers, same bearer
 * token handling; OkHttp stands in for URLSession.
 */
class ApiClient(
    context: Context,
    private val localeProvider: () -> String = { LocaleStore.current.code },
) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val baseUrl: HttpUrl = run {
        val scheme = BuildConfig.API_SCHEME.ifBlank { "https" }
        val host = BuildConfig.API_BASE_URL
        "$scheme://$host/".toHttpUrlOrNull() ?: throw ApiException.InvalidBaseUrl
    }

    private var sessionToken: String? = prefs.getString(SESSION_TOKEN_KEY, null)

    val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        coerceInputValues = true
        isLenient = true
        encodeDefaults = true
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(18, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .apply {
            // Debug builds log the exchange so a failure on a real device can be
            // read from logcat; the bearer token is redacted, and release builds
            // install no interceptor at all.
            if (BuildConfig.DEBUG) {
                addInterceptor(
                    HttpLoggingInterceptor { line -> Log.d("SportSearchHttp", line) }.apply {
                        level = HttpLoggingInterceptor.Level.BODY
                        redactHeader("Authorization")
                    },
                )
            }
        }
        .build()

    /** SSE keeps a much longer read timeout, mirroring `streamSession` on iOS. */
    private val streamClient = client.newBuilder()
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .connectTimeout(45, TimeUnit.SECONDS)
        .build()

    val effectiveLocaleIdentifier: String
        get() = localeProvider().lowercase().takeIf { it == "ru" || it == "en" } ?: "en"

    fun setSessionToken(token: String?) {
        val normalized = token?.trim()?.takeIf { it.isNotEmpty() }
        sessionToken = normalized
        prefs.edit().apply {
            if (normalized != null) putString(SESSION_TOKEN_KEY, normalized) else remove(SESSION_TOKEN_KEY)
        }.apply()
    }

    fun hasSessionToken(): Boolean = !sessionToken.isNullOrEmpty()

    private fun buildUrl(path: String, query: List<Pair<String, String?>>): HttpUrl {
        val builder = baseUrl.newBuilder()
        path.trim('/').split('/').filter { it.isNotEmpty() }.forEach(builder::addPathSegment)
        query.forEach { (name, value) ->
            if (value != null) builder.addQueryParameter(name, value)
        }
        return builder.build()
    }

    private fun newRequest(
        path: String,
        method: String,
        query: List<Pair<String, String?>>,
        body: RequestBody?,
    ): Request {
        val builder = Request.Builder()
            .url(buildUrl(path, query))
            .method(method, body)
            .header("Cache-Control", "no-cache")
            .header("Pragma", "no-cache")
            .header("Accept-Language", effectiveLocaleIdentifier)

        if (body == null || body.contentType() == null) {
            builder.header("Content-Type", "application/json")
        }
        sessionToken?.takeIf { it.isNotEmpty() }?.let { builder.header("Authorization", "Bearer $it") }
        return builder.build()
    }

    suspend fun <T> request(
        path: String,
        method: String = "GET",
        query: List<Pair<String, String?>> = emptyList(),
        jsonBody: String? = null,
        deserializer: KSerializer<T>,
    ): T {
        val body = when {
            jsonBody != null -> jsonBody.toRequestBody(JSON_MEDIA_TYPE)
            method != "GET" && method != "HEAD" -> "".toRequestBody(JSON_MEDIA_TYPE)
            else -> null
        }
        val payload = perform(newRequest(path, method, query, body))
        return decode(payload, deserializer)
    }

    /** For endpoints whose body is ignored (`markInboxSeen`, `setActiveChat`, ...). */
    suspend fun requestDiscardingResponse(
        path: String,
        method: String = "POST",
        query: List<Pair<String, String?>> = emptyList(),
        jsonBody: String? = null,
    ) {
        val body = when {
            jsonBody != null -> jsonBody.toRequestBody(JSON_MEDIA_TYPE)
            method != "GET" && method != "HEAD" -> "".toRequestBody(JSON_MEDIA_TYPE)
            else -> null
        }
        perform(newRequest(path, method, query, body))
    }

    suspend fun <T> uploadMultipart(
        path: String,
        fieldName: String,
        fileName: String,
        mimeType: String,
        bytes: ByteArray,
        deserializer: KSerializer<T>,
    ): T {
        val body = MultipartBody.Builder("Boundary-${UUID.randomUUID()}")
            .setType(MultipartBody.FORM)
            .addFormDataPart(
                fieldName,
                fileName,
                bytes.toRequestBody(mimeType.toMediaType()),
            )
            .build()
        val payload = perform(newRequest(path, "POST", emptyList(), body))
        return decode(payload, deserializer)
    }

    suspend fun download(path: String): ByteArray = withContext(Dispatchers.IO) {
        val absolute = path.toHttpUrlOrNull()?.takeIf { path.startsWith("http") }
        val request = if (absolute != null) {
            Request.Builder()
                .url(absolute)
                .header("Accept-Language", effectiveLocaleIdentifier)
                .build()
        } else {
            newRequest(path.removePrefix("/"), "GET", emptyList(), null)
        }

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw ApiException.Server("HTTP ${response.code}")
            response.body?.bytes() ?: throw ApiException.InvalidResponse
        }
    }

    /**
     * `realtimeEvents(lastEventId:)`. The backend speaks Server-Sent Events;
     * OkHttp has no SSE client in the core artifact, so the framing is parsed
     * here the same way the Swift byte-stream reader does.
     */
    fun realtimeEvents(lastEventId: String?): Flow<RealtimeEvent> = callbackFlow {
        val builder = Request.Builder()
            .url(buildUrl("realtime", emptyList()))
            .get()
            .header("Accept", "text/event-stream")
            .header("Cache-Control", "no-cache")
            .header("Accept-Language", effectiveLocaleIdentifier)
        sessionToken?.let { builder.header("Authorization", "Bearer $it") }
        lastEventId?.let { builder.header("Last-Event-ID", it) }

        val call = streamClient.newCall(builder.build())
        val response = try {
            call.execute()
        } catch (error: IOException) {
            close(error)
            return@callbackFlow
        }

        if (!response.isSuccessful) {
            response.close()
            close(ApiException.Server("HTTP ${response.code}"))
            return@callbackFlow
        }

        try {
            val source = response.body?.source() ?: throw ApiException.InvalidResponse
            var eventId: String? = null
            val dataLines = StringBuilder()

            while (!source.exhausted()) {
                val line = source.readUtf8LineStrict()
                when {
                    line.isEmpty() -> {
                        if (dataLines.isNotEmpty()) {
                            runCatching {
                                json.decodeFromString(RealtimeEvent.serializer(), dataLines.toString())
                            }.getOrNull()?.let { event ->
                                trySend(eventId?.let { event.copy(id = it) } ?: event)
                            }
                        }
                        eventId = null
                        dataLines.clear()
                    }
                    line.startsWith("id:") -> eventId = line.removePrefix("id:").trim()
                    line.startsWith("data:") -> dataLines.append(line.removePrefix("data:").trim())
                    else -> Unit // comments and retry hints are ignored, as on iOS
                }
            }
            close()
        } catch (error: Throwable) {
            close(error)
        }

        awaitClose {
            call.cancel()
            response.close()
        }
    }.flowOn(Dispatchers.IO)

    private suspend fun perform(request: Request): String = withContext(Dispatchers.IO) {
        val response: Response = try {
            client.newCall(request).execute()
        } catch (error: IOException) {
            throw ApiException.Server(error.message ?: "Network error")
        }

        response.use {
            val text = it.body?.string().orEmpty()
            if (!it.isSuccessful) {
                val serverError = runCatching {
                    json.decodeFromString(ErrorEnvelope.serializer(), text).error
                }.getOrNull() ?: "HTTP ${it.code}. ${debugPayloadSummary(text, it)}"
                throw ApiException.Server(serverError)
            }
            text
        }
    }

    private fun <T> decode(payload: String, deserializer: KSerializer<T>): T =
        try {
            if (deserializer == Unit.serializer()) {
                @Suppress("UNCHECKED_CAST")
                Unit as T
            } else {
                json.decodeFromString(deserializer, payload)
            }
        } catch (error: Throwable) {
            throw ApiException.InvalidPayload(
                "Не удалось прочитать JSON ответа. ${error.message ?: ""}. " +
                    payload.take(220),
            )
        }

    fun encodeToString(element: JsonElement): String = json.encodeToString(JsonElement.serializer(), element)

    /** Absolute URL for a server-relative media path, for Coil. */
    fun absoluteUrl(path: String?): String? {
        if (path.isNullOrBlank()) return null
        if (path.startsWith("http://") || path.startsWith("https://")) return path
        return baseUrl.newBuilder().encodedPath("/").build().toString().trimEnd('/') + "/" + path.trimStart('/')
    }

    private fun debugPayloadSummary(text: String, response: Response): String {
        val contentType = response.header("Content-Type") ?: "unknown content type"
        return "Content-Type: $contentType. Body: ${text.take(220)}"
    }

    companion object {
        private const val PREFS_NAME = "sportsearch.session"

        /** Same key name the iOS client writes, for parity when debugging. */
        private const val SESSION_TOKEN_KEY = "SportSearch.sessionToken"

        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}

@kotlinx.serialization.Serializable
internal data class ErrorEnvelope(val error: String = "")
