package shop.sportsearch.app.ui.profile

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.OptIn
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.transformer.Composition
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import java.io.File
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import shop.sportsearch.app.core.L10n

/** The longest clip the profile accepts, matching iOS. */
const val PROFILE_VIDEO_CLIP_SECONDS = 10.0

/** Port of `private struct ProfileVideoTrimDraft`. */
data class ProfileVideoTrimDraft(
    val sourceFile: File,
    val duration: Double,
    val fileName: String,
)

/** Port of `private struct ProfileTrimmedVideoPayload`. */
data class ProfileTrimmedVideoPayload(
    val bytes: ByteArray,
    val fileExtension: String,
    val mimeType: String,
) {
    override fun equals(other: Any?): Boolean =
        this === other || (other is ProfileTrimmedVideoPayload && bytes.contentEquals(other.bytes))

    override fun hashCode(): Int = bytes.contentHashCode()
}

/**
 * The system picker restricted to videos, mirroring the iOS
 * `PhotosPicker(matching: .videos)` next to the photo one.
 */
@Composable
fun rememberProfileVideoPicker(maxItems: Int, onPicked: (List<Uri>) -> Unit): () -> Unit {
    val launcher = rememberLauncherForActivityResult(
        // `PickMultipleVisualMedia` rejects a max of 1, so a single slot uses the
        // single-item contract instead.
        ActivityResultContracts.PickMultipleVisualMedia(maxOf(maxItems, 2)),
    ) { uris ->
        if (uris.isNotEmpty()) onPicked(uris.take(maxOf(maxItems, 1)))
    }
    LocalContext.current
    return {
        launcher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly))
    }
}

/**
 * Port of `prepareNextVideoTrimDraft()` - copies the picked video into the cache
 * directory so the player and the trimmer can both read it, then measures it.
 */
suspend fun prepareProfileVideoTrimDraft(context: Context, uri: Uri): ProfileVideoTrimDraft =
    withContext(Dispatchers.IO) {
        val extension = context.contentResolver.getType(uri)
            ?.let { type -> if (type.endsWith("/quicktime")) "mov" else "mp4" }
            ?: "mp4"
        val target = File(context.cacheDir, "profile-video-source-${UUID.randomUUID()}.$extension")

        context.contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use(input::copyTo)
        } ?: throw IllegalStateException(
            L10n.string("Could not read the selected video", "Не удалось прочитать выбранное видео"),
        )

        // `MediaMetadataRetriever` only became `AutoCloseable` in API 29, and this
        // app still supports 26, so it is released by hand.
        val retriever = MediaMetadataRetriever()
        val durationMs = try {
            retriever.setDataSource(target.absolutePath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
        } finally {
            retriever.release()
        }

        if (durationMs == null || durationMs <= 0) {
            target.delete()
            throw IllegalStateException(
                L10n.string(
                    "Could not determine the video duration",
                    "Не удалось определить длительность видео",
                ),
            )
        }

        ProfileVideoTrimDraft(
            sourceFile = target,
            duration = durationMs / 1000.0,
            fileName = "profile-video-${UUID.randomUUID()}",
        )
    }

/**
 * Port of `trimmedVideoPayload(from:startTime:)`. iOS cuts the clip with
 * `AVAssetExportSession` at medium quality; media3's `Transformer` is the same
 * tool here, and the clip window is expressed as a `ClippingConfiguration`.
 *
 * A frame-accurate cut has to decode and re-encode. Where the device codecs
 * refuse that, the clip is copied through instead, snapped back to the nearest
 * keyframe - a slightly earlier start beats no video at all.
 */
@OptIn(UnstableApi::class)
suspend fun trimProfileVideo(
    context: Context,
    draft: ProfileVideoTrimDraft,
    startTime: Double,
): ProfileTrimmedVideoPayload {
    val safeStart = startTime.coerceIn(0.0, maxOf(draft.duration - 0.2, 0.0))
    val clipDuration = minOf(PROFILE_VIDEO_CLIP_SECONDS, maxOf(draft.duration - safeStart, 0.2))

    val bytes = try {
        exportClip(context, draft, safeStart, clipDuration, startsAtKeyFrame = false)
    } catch (error: ExportException) {
        exportClip(context, draft, safeStart, clipDuration, startsAtKeyFrame = true)
    }

    if (bytes.isEmpty()) {
        throw IllegalStateException(
            L10n.string(
                "Could not prepare the video for trimming",
                "Не удалось подготовить видео к обрезке",
            ),
        )
    }

    return ProfileTrimmedVideoPayload(bytes = bytes, fileExtension = "mp4", mimeType = "video/mp4")
}

@OptIn(UnstableApi::class)
private suspend fun exportClip(
    context: Context,
    draft: ProfileVideoTrimDraft,
    startSeconds: Double,
    durationSeconds: Double,
    startsAtKeyFrame: Boolean,
): ByteArray {
    val output = File(context.cacheDir, "profile-video-trimmed-${UUID.randomUUID()}.mp4")

    val mediaItem = MediaItem.Builder()
        .setUri(Uri.fromFile(draft.sourceFile))
        .setClippingConfiguration(
            MediaItem.ClippingConfiguration.Builder()
                .setStartPositionMs((startSeconds * 1000).toLong())
                .setEndPositionMs(((startSeconds + durationSeconds) * 1000).toLong())
                .setStartsAtKeyFrame(startsAtKeyFrame)
                .build(),
        )
        .build()

    try {
        // `Transformer` needs a Looper, and its callbacks land on the thread that
        // started it, so the whole export runs on the main dispatcher.
        withContext(Dispatchers.Main) {
            suspendCancellableCoroutine { continuation ->
                val builder = Transformer.Builder(context)
                if (!startsAtKeyFrame) {
                    builder.setVideoMimeType(MimeTypes.VIDEO_H264)
                        .setAudioMimeType(MimeTypes.AUDIO_AAC)
                }
                val transformer = builder
                    .addListener(
                        object : Transformer.Listener {
                            override fun onCompleted(composition: Composition, result: ExportResult) {
                                if (continuation.isActive) continuation.resume(Unit)
                            }

                            override fun onError(
                                composition: Composition,
                                result: ExportResult,
                                exception: ExportException,
                            ) {
                                if (continuation.isActive) continuation.resumeWithException(exception)
                            }
                        },
                    )
                    .build()

                continuation.invokeOnCancellation { transformer.cancel() }
                transformer.start(mediaItem, output.absolutePath)
            }
        }

        return withContext(Dispatchers.IO) { output.readBytes() }
    } finally {
        output.delete()
    }
}
