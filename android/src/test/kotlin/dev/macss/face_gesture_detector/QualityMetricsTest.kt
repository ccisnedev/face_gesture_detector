package dev.macss.face_gesture_detector

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [QualityMetrics] on synthetic luminance planes.
 */
class QualityMetricsTest {

    private fun flat(width: Int, height: Int, value: Int): ByteArray =
        ByteArray(width * height) { value.toByte() }

    /** Vertical stripes alternating between [a] and [b] every [period] px. */
    private fun stripes(width: Int, height: Int, a: Int, b: Int, period: Int): ByteArray {
        val out = ByteArray(width * height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                out[y * width + x] = (if ((x / period) % 2 == 0) a else b).toByte()
            }
        }
        return out
    }

    // ── brightness ──────────────────────────────────────────────

    @Test
    fun `brightness of a black frame is 0`() {
        assertEquals(0.0, QualityMetrics.brightness(flat(64, 48, 0), 64, 48), 1e-9)
    }

    @Test
    fun `brightness of a white frame is 1`() {
        assertEquals(1.0, QualityMetrics.brightness(flat(64, 48, 255), 64, 48), 1e-9)
    }

    @Test
    fun `brightness of a mid grey frame is about 0_5`() {
        val value = 128
        val expected = value / 255.0
        assertEquals(expected, QualityMetrics.brightness(flat(64, 48, value), 64, 48), 1e-9)
    }

    @Test
    fun `brightness subsampling matches full sampling on uniform data`() {
        val plane = flat(640, 480, 200)
        val full = QualityMetrics.brightness(plane, 640, 480, step = 1)
        val sub = QualityMetrics.brightness(plane, 640, 480, step = 4)
        assertEquals(full, sub, 1e-9)
    }

    @Test
    fun `brightness of half black half white is about 0_5`() {
        val width = 64
        val height = 64
        val plane = ByteArray(width * height) { i -> if (i < width * height / 2) 0 else 255.toByte() }
        assertEquals(0.5, QualityMetrics.brightness(plane, width, height, step = 1), 1e-9)
    }

    @Test
    fun `brightness returns 0 for truncated plane`() {
        assertEquals(0.0, QualityMetrics.brightness(ByteArray(10), 64, 48), 1e-9)
    }

    // ── sharpness ───────────────────────────────────────────────

    @Test
    fun `sharpness of a flat frame is 0`() {
        assertEquals(0.0, QualityMetrics.sharpness(flat(320, 240, 100), 320, 240), 1e-9)
    }

    @Test
    fun `sharpness of a high contrast stripe pattern is high`() {
        // 1-px stripes evaluated at step 1 (region 160 px wide → step = 1).
        val plane = stripes(320, 240, 0, 255, 1)
        val value = QualityMetrics.sharpness(plane, 320, 240, PixelRect(80, 60, 160, 120))
        assertTrue("expected high sharpness, got $value", value > 10_000.0)
    }

    @Test
    fun `sharpness increases with contrast`() {
        val low = stripes(320, 240, 100, 120, 1)
        val high = stripes(320, 240, 0, 255, 1)
        val region = PixelRect(80, 60, 160, 120)
        val sLow = QualityMetrics.sharpness(low, 320, 240, region)
        val sHigh = QualityMetrics.sharpness(high, 320, 240, region)
        assertTrue("low=$sLow high=$sHigh", sHigh > sLow && sLow > 0.0)
    }

    @Test
    fun `sharpness region outside the image is clamped`() {
        val plane = stripes(320, 240, 0, 255, 1)
        val partlyOutside = PixelRect(300, 200, 400, 400)
        val value = QualityMetrics.sharpness(plane, 320, 240, partlyOutside)
        assertTrue(value > 0.0)
    }

    @Test
    fun `sharpness region fully outside the image is 0`() {
        val plane = stripes(320, 240, 0, 255, 1)
        assertEquals(0.0, QualityMetrics.sharpness(plane, 320, 240, PixelRect(400, 400, 10, 10)), 1e-9)
    }

    @Test
    fun `sharpness defaults to the central region when none is given`() {
        // Edges sharp, centre flat → default (centre) region must report ~0.
        val width = 320
        val height = 240
        val plane = stripes(width, height, 0, 255, 1)
        val centre = QualityMetrics.centerRegion(width, height)
        for (y in centre.top until centre.bottom) {
            for (x in centre.left until centre.right) {
                plane[y * width + x] = 128.toByte()
            }
        }
        assertEquals(0.0, QualityMetrics.sharpness(plane, width, height), 1e-9)
    }

    // ── helpers ─────────────────────────────────────────────────

    @Test
    fun `centerRegion covers the middle half`() {
        assertEquals(PixelRect(160, 120, 320, 240), QualityMetrics.centerRegion(640, 480))
    }

    @Test
    fun `clampRegion intersects with image bounds`() {
        assertEquals(PixelRect(0, 0, 10, 10), QualityMetrics.clampRegion(PixelRect(-5, -5, 15, 15), 100, 100))
        assertEquals(PixelRect(90, 90, 10, 10), QualityMetrics.clampRegion(PixelRect(90, 90, 50, 50), 100, 100))
        assertNull(QualityMetrics.clampRegion(PixelRect(100, 0, 10, 10), 100, 100))
    }

    @Test
    fun `lumaFromArgb weights channels with BT601 approximation`() {
        val white = 0xFFFFFFFF.toInt()
        val black = 0xFF000000.toInt()
        val green = 0xFF00FF00.toInt()
        val luma = QualityMetrics.lumaFromArgb(intArrayOf(white, black, green))
        assertEquals(255, luma[0].toInt() and 0xFF)
        assertEquals(0, luma[1].toInt() and 0xFF)
        assertEquals((150 * 255) shr 8, luma[2].toInt() and 0xFF)
    }
}
