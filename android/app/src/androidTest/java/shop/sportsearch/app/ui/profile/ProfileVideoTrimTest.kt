package shop.sportsearch.app.ui.profile

import android.media.MediaMetadataRetriever
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The trim path is the one piece of the profile video flow with no pure-Kotlin
 * equivalent - it leans on the device codecs - so it is checked on a device.
 */
@RunWith(AndroidJUnit4::class)
class ProfileVideoTrimTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var source: File

    @Before
    fun copySampleVideo() {
        source = File(context.cacheDir, "trim-test-source.mp4")
        InstrumentationRegistry.getInstrumentation().context.assets.open("trim-test.mp4").use { input ->
            source.outputStream().use(input::copyTo)
        }
    }

    @After
    fun cleanUp() {
        source.delete()
    }

    @Test
    fun readsTheDurationOfThePickedVideo(): Unit = runBlocking {
        val draft = prepareProfileVideoTrimDraft(context, android.net.Uri.fromFile(source))
        assertEquals(25.0, draft.duration, 0.5)
        assertTrue(draft.sourceFile.exists())
        draft.sourceFile.delete()
    }

    @Test
    fun cutsATenSecondClipFromTheMiddle(): Unit = runBlocking {
        val draft = prepareProfileVideoTrimDraft(context, android.net.Uri.fromFile(source))
        val payload = trimProfileVideo(context, draft, startTime = 8.0)

        assertEquals("video/mp4", payload.mimeType)
        assertTrue("expected a non-empty clip", payload.bytes.size > 1024)

        val clip = File(context.cacheDir, "trim-test-output.mp4")
        clip.writeBytes(payload.bytes)
        val retriever = MediaMetadataRetriever()
        val durationMs = try {
            retriever.setDataSource(clip.absolutePath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong()
        } finally {
            retriever.release()
        }
        clip.delete()
        draft.sourceFile.delete()

        assertEquals(10_000.0, durationMs.toDouble(), 600.0)
    }

    @Test
    fun clampsAClipThatWouldRunPastTheEnd(): Unit = runBlocking {
        val draft = prepareProfileVideoTrimDraft(context, android.net.Uri.fromFile(source))
        val payload = trimProfileVideo(context, draft, startTime = 21.0)

        val clip = File(context.cacheDir, "trim-test-tail.mp4")
        clip.writeBytes(payload.bytes)
        val retriever = MediaMetadataRetriever()
        val durationMs = try {
            retriever.setDataSource(clip.absolutePath)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)!!.toLong()
        } finally {
            retriever.release()
        }
        clip.delete()
        draft.sourceFile.delete()

        // 25 s source, start at 21 s -> only 4 s left, not the full 10.
        assertEquals(4_000.0, durationMs.toDouble(), 600.0)
    }
}
