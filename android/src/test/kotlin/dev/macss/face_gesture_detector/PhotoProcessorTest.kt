package dev.macss.face_gesture_detector

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure geometry helpers of [PhotoProcessor].
 */
class PhotoProcessorTest {

    // ── computeCropRect ─────────────────────────────────────────

    @Test
    fun `crop without margin or aspect equals the face rect`() {
        val face = NormalizedRect(0.25, 0.25, 0.5, 0.5)
        val crop = PhotoProcessor.computeCropRect(1000, 1000, face, 0.0, null)
        assertEquals(PixelRect(250, 250, 500, 500), crop)
    }

    @Test
    fun `margin expands the crop around the face centre`() {
        val face = NormalizedRect(0.4, 0.4, 0.2, 0.2) // centre (500, 500), 200×200
        val crop = PhotoProcessor.computeCropRect(1000, 1000, face, 0.5, null)
        assertEquals(PixelRect(350, 350, 300, 300), crop)
    }

    @Test
    fun `aspect ratio enlarges the shorter side`() {
        val face = NormalizedRect(0.4, 0.4, 0.2, 0.2) // 200×200
        val crop = PhotoProcessor.computeCropRect(1000, 1000, face, 0.0, 0.75)
        // Aspect 3:4 → width 200, height 200/0.75 = 267, centred on (500, 500)
        assertEquals(200, crop.width)
        assertEquals(267, crop.height)
        assertEquals(400, crop.left)
        assertEquals(367, crop.top)
    }

    @Test
    fun `crop is shifted inside the image when the face is near an edge`() {
        val face = NormalizedRect(0.0, 0.0, 0.2, 0.2)
        val crop = PhotoProcessor.computeCropRect(1000, 1000, face, 1.0, null)
        assertEquals(0, crop.left)
        assertEquals(0, crop.top)
        assertEquals(400, crop.width)
        assertEquals(400, crop.height)
    }

    @Test
    fun `crop never exceeds the image and keeps the aspect when shrunk`() {
        val face = NormalizedRect(0.1, 0.1, 0.8, 0.8)
        val crop = PhotoProcessor.computeCropRect(600, 800, face, 1.0, 0.75)
        assertTrue(crop.left >= 0 && crop.top >= 0)
        assertTrue(crop.right <= 600 && crop.bottom <= 800)
        assertEquals(0.75, crop.width.toDouble() / crop.height, 0.01)
    }

    @Test
    fun `crop of a face covering the whole image is the whole image`() {
        val face = NormalizedRect(0.0, 0.0, 1.0, 1.0)
        val crop = PhotoProcessor.computeCropRect(640, 480, face, 0.6, null)
        assertEquals(PixelRect(0, 0, 640, 480), crop)
    }

    @Test
    fun `mirrored rect flips horizontally`() {
        val face = NormalizedRect(0.1, 0.2, 0.3, 0.4)
        val mirrored = face.mirrored()
        assertEquals(0.6, mirrored.left, 1e-9)
        assertEquals(0.2, mirrored.top, 1e-9)
        assertEquals(0.3, mirrored.width, 1e-9)
        assertEquals(0.4, mirrored.height, 1e-9)
    }

    // ── computeInSampleSize ─────────────────────────────────────

    @Test
    fun `inSampleSize is 1 when the image already fits the target`() {
        assertEquals(1, PhotoProcessor.computeInSampleSize(1080, 1440, 1080))
        assertEquals(1, PhotoProcessor.computeInSampleSize(720, 960, 1080))
    }

    @Test
    fun `inSampleSize halves while the short side stays above the target`() {
        // 3000×4000 → short 3000: /2 = 1500 ≥ 1080 ok, /4 = 750 < 1080 stop → 2
        assertEquals(2, PhotoProcessor.computeInSampleSize(3000, 4000, 1080))
        // 4800×6400 → /2 = 2400, /4 = 1200 ≥ 1080 ok, /8 = 600 stop → 4
        assertEquals(4, PhotoProcessor.computeInSampleSize(4800, 6400, 1080))
    }

    @Test
    fun `inSampleSize is 1 for a non positive target`() {
        assertEquals(1, PhotoProcessor.computeInSampleSize(4000, 3000, 0))
    }
}
