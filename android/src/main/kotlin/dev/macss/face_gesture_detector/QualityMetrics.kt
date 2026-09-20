package dev.macss.face_gesture_detector

import kotlin.math.max
import kotlin.math.min

/**
 * Integer rectangle in pixel coordinates. [left]/[top] are inclusive,
 * [width]/[height] are sizes in pixels.
 */
data class PixelRect(val left: Int, val top: Int, val width: Int, val height: Int) {
    val right: Int get() = left + width
    val bottom: Int get() = top + height
}

/**
 * Image quality metrics computed on a luminance plane (8-bit, row-major,
 * stride == width). Pure Kotlin — no Android dependencies — so it can be
 * unit-tested on the JVM and shared by the live camera pipeline (NV21 Y
 * plane) and the captured-photo processor (luma derived from ARGB).
 */
object QualityMetrics {

    /** Sample every Nth pixel in both axes when computing brightness. */
    const val DEFAULT_BRIGHTNESS_STEP = 4

    /**
     * Target sampled width of the sharpness region. The region is subsampled
     * so that roughly this many columns are evaluated, keeping the cost
     * bounded (< 2 ms) regardless of the source resolution.
     */
    const val DEFAULT_SHARPNESS_TARGET_WIDTH = 160

    /**
     * Mean luminance of the plane, subsampled by [step], normalized to 0..1.
     * Returns 0.0 for empty or truncated planes.
     */
    fun brightness(
        luma: ByteArray,
        width: Int,
        height: Int,
        step: Int = DEFAULT_BRIGHTNESS_STEP,
    ): Double {
        if (width <= 0 || height <= 0 || luma.size < width * height) return 0.0
        val s = max(1, step)
        var sum = 0L
        var count = 0L
        var y = 0
        while (y < height) {
            val row = y * width
            var x = 0
            while (x < width) {
                sum += luma[row + x].toInt() and 0xFF
                count++
                x += s
            }
            y += s
        }
        return if (count == 0L) 0.0 else sum.toDouble() / (count * 255.0)
    }

    /**
     * Variance of the Laplacian over [region] (defaults to the central 50 %
     * of the plane). Higher values mean more high-frequency detail, i.e. a
     * sharper image; a flat or heavily blurred region tends towards 0.
     *
     * The region is evaluated on a grid with spacing `step = regionWidth /
     * targetWidth` (at least 1), and the Laplacian uses the four neighbours
     * at that same spacing. Values are therefore comparable across
     * resolutions for the same [targetWidth].
     */
    fun sharpness(
        luma: ByteArray,
        width: Int,
        height: Int,
        region: PixelRect? = null,
        targetWidth: Int = DEFAULT_SHARPNESS_TARGET_WIDTH,
    ): Double {
        if (width <= 0 || height <= 0 || luma.size < width * height) return 0.0
        val r = clampRegion(region ?: centerRegion(width, height), width, height) ?: return 0.0
        val step = max(1, r.width / max(1, targetWidth))
        val cols = r.width / step
        val rows = r.height / step
        if (cols < 3 || rows < 3) return 0.0

        var sum = 0.0
        var sumSq = 0.0
        var n = 0L
        for (gy in 1 until rows - 1) {
            val y = r.top + gy * step
            val rowUp = (y - step) * width
            val row = y * width
            val rowDown = (y + step) * width
            for (gx in 1 until cols - 1) {
                val x = r.left + gx * step
                val c = luma[row + x].toInt() and 0xFF
                val l = luma[row + x - step].toInt() and 0xFF
                val rr = luma[row + x + step].toInt() and 0xFF
                val u = luma[rowUp + x].toInt() and 0xFF
                val d = luma[rowDown + x].toInt() and 0xFF
                val lap = (4 * c - l - rr - u - d).toDouble()
                sum += lap
                sumSq += lap * lap
                n++
            }
        }
        if (n == 0L) return 0.0
        val mean = sum / n
        return max(0.0, sumSq / n - mean * mean)
    }

    /** Central region covering 50 % of each dimension. */
    fun centerRegion(width: Int, height: Int): PixelRect {
        val w = max(1, width / 2)
        val h = max(1, height / 2)
        return PixelRect((width - w) / 2, (height - h) / 2, w, h)
    }

    /** Intersects [region] with the image bounds; null when empty. */
    fun clampRegion(region: PixelRect, width: Int, height: Int): PixelRect? {
        val left = max(0, region.left)
        val top = max(0, region.top)
        val right = min(width, region.right)
        val bottom = min(height, region.bottom)
        if (right - left <= 0 || bottom - top <= 0) return null
        return PixelRect(left, top, right - left, bottom - top)
    }

    /**
     * Converts ARGB_8888 pixels to an 8-bit luma plane using the integer
     * BT.601 approximation `(77 R + 150 G + 29 B) >> 8`.
     */
    fun lumaFromArgb(pixels: IntArray): ByteArray {
        val out = ByteArray(pixels.size)
        for (i in pixels.indices) {
            val p = pixels[i]
            val r = (p shr 16) and 0xFF
            val g = (p shr 8) and 0xFF
            val b = p and 0xFF
            out[i] = ((77 * r + 150 * g + 29 * b) shr 8).toByte()
        }
        return out
    }
}
