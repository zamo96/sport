package shop.sportsearch.app.ui.components

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BrokenImage
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import shop.sportsearch.app.core.L10n
import shop.sportsearch.app.data.TennisRepository
import shop.sportsearch.app.ui.theme.AppTheme
import shop.sportsearch.app.ui.theme.continuousShape
import java.io.ByteArrayOutputStream
import java.util.UUID

/** Port of `PendingMatchChatPhoto` / `PendingSearchChatPhoto`. */
data class PendingChatPhoto(
    val id: String = UUID.randomUUID().toString(),
    val bytes: ByteArray,
    val preview: ImageBitmap,
    val fileName: String,
    val mimeType: String,
) {
    // ByteArray gives structural equality by reference, so the generated
    // equals/hashCode would be wrong for a data class used as list state.
    override fun equals(other: Any?): Boolean = other is PendingChatPhoto && other.id == id
    override fun hashCode(): Int = id.hashCode()
}

/** iOS caps a chat pick at 4 photos. */
private const val MAX_CHAT_PHOTOS = 4

/** iOS re-encodes each pick with `jpegData(compressionQuality: 0.88)`. */
private const val JPEG_QUALITY = 88

/** Long edge cap so a 12MP phone photo does not become a 6MB upload. */
private const val MAX_UPLOAD_EDGE = 1600

/**
 * The system photo picker. It needs no storage permission on any supported API
 * level, which is why it is used instead of a `READ_MEDIA_IMAGES` flow.
 */
@Composable
fun rememberChatPhotoPicker(
    onPicked: (List<PendingChatPhoto>) -> Unit,
): () -> Unit {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    val launcher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(MAX_CHAT_PHOTOS),
    ) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        scope.launch {
            val loaded = withContext(Dispatchers.IO) {
                uris.take(MAX_CHAT_PHOTOS).mapIndexedNotNull { index, uri ->
                    loadPendingPhoto(context, uri, index)
                }
            }
            if (loaded.isNotEmpty()) onPicked(loaded)
        }
    }

    return {
        launcher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
    }
}

private fun loadPendingPhoto(context: Context, uri: Uri, index: Int): PendingChatPhoto? = runCatching {
    val original = context.contentResolver.openInputStream(uri)?.use(BitmapFactory::decodeStream)
        ?: return@runCatching null

    val longEdge = maxOf(original.width, original.height)
    val scaled = if (longEdge > MAX_UPLOAD_EDGE) {
        val ratio = MAX_UPLOAD_EDGE.toFloat() / longEdge
        Bitmap.createScaledBitmap(
            original,
            (original.width * ratio).toInt().coerceAtLeast(1),
            (original.height * ratio).toInt().coerceAtLeast(1),
            true,
        )
    } else {
        original
    }

    val stream = ByteArrayOutputStream()
    scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, stream)

    PendingChatPhoto(
        bytes = stream.toByteArray(),
        preview = scaled.asImageBitmap(),
        fileName = "chat-photo-${index + 1}.jpg",
        mimeType = "image/jpeg",
    )
}.getOrNull()

/** The strip of picked-but-not-yet-sent photos above the composer. */
@Composable
fun PendingPhotosRail(
    photos: List<PendingChatPhoto>,
    onRemove: (PendingChatPhoto) -> Unit,
    modifier: Modifier = Modifier,
    thumbnailSize: Dp = 70.dp,
) {
    if (photos.isEmpty()) return

    Row(
        modifier = modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        photos.forEach { photo ->
            Box(modifier = Modifier.padding(top = 5.dp, end = 5.dp)) {
                androidx.compose.foundation.Image(
                    bitmap = photo.preview,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(thumbnailSize)
                        .clip(continuousShape(14.dp)),
                )
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .offset(x = 5.dp, y = (-5).dp)
                        .size(22.dp)
                        .clip(CircleShape)
                        .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.7f))
                        .clickable { onRemove(photo) },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Filled.Close,
                        contentDescription = L10n.string("Remove", "Убрать"),
                        tint = androidx.compose.ui.graphics.Color.White,
                        modifier = Modifier.size(14.dp),
                    )
                }
            }
        }
    }
}

/**
 * Port of `struct RemoteChatMediaImage`.
 *
 * Chat media is served behind the session token, so the bytes are fetched
 * through the repository (which attaches the bearer) rather than handed to Coil
 * as a plain URL.
 */
@Composable
fun RemoteChatMediaImage(
    repository: TennisRepository,
    path: String,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Crop,
) {
    var image by remember(path) { mutableStateOf<ImageBitmap?>(null) }
    var failed by remember(path) { mutableStateOf(false) }

    LaunchedEffect(path) {
        image = null
        failed = false
        val loaded = withContext(Dispatchers.IO) {
            runCatching {
                val bytes = repository.fetchChatMedia(path)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
            }.getOrNull()
        }
        if (loaded != null) image = loaded else failed = true
    }

    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        when {
            image != null -> androidx.compose.foundation.Image(
                bitmap = image!!,
                contentDescription = null,
                contentScale = contentScale,
                modifier = Modifier.fillMaxSize(),
            )
            failed -> Icon(
                Icons.Filled.BrokenImage,
                contentDescription = null,
                tint = AppTheme.mutedInk,
                modifier = Modifier.size(24.dp),
            )
            else -> CircularProgressIndicator(color = AppTheme.court, strokeWidth = 2.dp, modifier = Modifier.size(20.dp))
        }
    }
}

/** Port of `SearchChatMediaViewer`: the full-screen tap-to-open viewer. */
@Composable
fun ChatMediaViewer(
    repository: TennisRepository,
    path: String,
    onDismiss: () -> Unit,
) {
    DismissOnSystemBack(onDismiss)
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(androidx.compose.ui.graphics.Color.Black),
    ) {
        RemoteChatMediaImage(
            repository = repository,
            path = path,
            contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxSize(),
        )

        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(20.dp)
                .size(34.dp)
                .clip(CircleShape)
                .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.55f))
                .clickable(onClick = onDismiss),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Filled.Close,
                contentDescription = L10n.string("Close", "Закрыть"),
                tint = androidx.compose.ui.graphics.Color.White,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

/** The attachment grid inside a chat bubble: one big image, or a 2-column grid. */
@Composable
fun ChatAttachmentsGrid(
    repository: TennisRepository,
    attachments: List<shop.sportsearch.app.core.ChatMediaAttachment>,
    onOpen: (shop.sportsearch.app.core.ChatMediaAttachment) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (attachments.isEmpty()) return

    val sorted = attachments.sortedBy { it.position }
    val single = sorted.size == 1
    val shape = continuousShape(14.dp)

    androidx.compose.foundation.layout.Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        sorted.chunked(if (single) 1 else 2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { attachment ->
                    RemoteChatMediaImage(
                        repository = repository,
                        path = attachment.url,
                        modifier = Modifier
                            .size(
                                width = if (single) 210.dp else 100.dp,
                                height = if (single) 180.dp else 100.dp,
                            )
                            .clip(shape)
                            .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.08f))
                            .clickable { onOpen(attachment) },
                    )
                }
            }
        }
    }
}
