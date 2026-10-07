package dev.macss.face_gesture_detector

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Rectangle normalized to 0..1 relative to an *upright* image
 * (after EXIF orientation has been applied).
 */
data class NormalizedRect(
    val left: Double,
    val top: Double,
    val width: Double,
    val height: Double,
) {
    /** Mirrors the rectangle horizontally (x' = 1 - x - w). */
    fun mirrored(): NormalizedRect = NormalizedRect(1.0 - left - width, top, width, height)
}

/** Arguments of `processCapturedPhoto`, as received from Dart. */
data class CaptureProcessingArgs(
    val path: String,
    val mirror: Boolean,
    val faceRect: NormalizedRect?,
    val marginFactor: Double,
    val aspectRatio: Double?,
    val targetShortSide: Int,
    val jpegQuality: Int,
    val outputDir: String?,
)

/**
 * Turns a full-resolution JPEG from `CameraController.takePicture()` into a
 * face photo ready for storage or biometric comparison:
 *
 *   EXIF orientation → optional mirror → crop around the face → downscale
 *   (never upscale) → JPEG → quality metrics of the result.
 *
 * The geometry helpers ([computeCropRect], [computeInSampleSize]) are pure
 * and unit-tested on the JVM; [process] needs an Android runtime.
 */
object PhotoProcessor {

    private const val FILE_PREFIX = "fgd_capture_"

    /**
     * Crop rectangle (pixels) around [face], expanded by [marginFactor]
     * (0.6 = 60 % extra width and height) and, when [aspectRatio] (w/h)
     * is given, enlarged to that aspect. The result is shifted and clipped
     * so it always lies inside the image.
     */
    fun computeCropRect(
        imageWidth: Int,
        imageHeight: Int,
        face: NormalizedRect,
        marginFactor: Double,
        aspectRatio: Double?,
    ): PixelRect {
        require(imageWidth > 0 && imageHeight > 0) { "image must not be empty" }

        val fx = face.left * imageWidth
        val fy = face.top * imageHeight
        val fw = max(1.0, face.width * imageWidth)
        val fh = max(1.0, face.height * imageHeight)
        val cx = fx + fw / 2.0
        val cy = fy + fh / 2.0

        val margin = max(0.0, marginFactor)
        var w = fw * (1.0 + margin)
        var h = fh * (1.0 + margin)

        val aspect = aspectRatio?.takeIf { it > 0.0 }
        if (aspect != null) {
            if (w / h > aspect) h = w / aspect else w = h * aspect
        }

        // Fit inside the image. When an aspect is requested, shrink both
        // sides proportionally so the aspect survives.
        if (w > imageWidth) {
            val s = imageWidth / w
            w = imageWidth.toDouble()
            if (aspect != null) h *= s
        }
        if (h > imageHeight) {
            val s = imageHeight / h
            h = imageHeight.toDouble()
            if (aspect != null) w *= s
        }

        val left = (cx - w / 2.0).coerceIn(0.0, imageWidth - w)
        val top = (cy - h / 2.0).coerceIn(0.0, imageHeight - h)

        val l = left.roundToInt().coerceIn(0, imageWidth - 1)
        val t = top.roundToInt().coerceIn(0, imageHeight - 1)
        val cw = w.roundToInt().coerceIn(1, imageWidth - l)
        val ch = h.roundToInt().coerceIn(1, imageHeight - t)
        return PixelRect(l, t, cw, ch)
    }

    /**
     * Largest power-of-two `inSampleSize` that keeps the short side of the
     * decoded bitmap at or above [targetShortSide]. Returns 1 when the
     * target is not positive.
     */
    fun computeInSampleSize(width: Int, height: Int, targetShortSide: Int): Int {
        if (targetShortSide <= 0 || width <= 0 || height <= 0) return 1
        val shortSide = min(width, height)
        var sample = 1
        while (shortSide / (sample * 2) >= targetShortSide) {
            sample *= 2
        }
        return sample
    }

    /** Runs the full pipeline. Must be called off the main thread. */
    fun process(context: Context, args: CaptureProcessingArgs): Map<String, Any?> {
        val source = File(args.path)
        require(source.isFile) { "File not found: ${args.path}" }

        val exif = ExifInterface(args.path)
        val rotation = exif.rotationDegrees
        val flipped = exif.isFlipped

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(args.path, bounds)
        val opts = BitmapFactory.Options().apply {
            inSampleSize = computeInSampleSize(bounds.outWidth, bounds.outHeight, args.targetShortSide)
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        var bitmap = BitmapFactory.decodeFile(args.path, opts)
            ?: throw IllegalArgumentException("Cannot decode image: ${args.path}")

        // Orientation + mirror in one transform.
        val matrix = Matrix()
        if (flipped) matrix.postScale(-1f, 1f)
        if (rotation != 0) matrix.postRotate(rotation.toFloat())
        if (args.mirror) matrix.postScale(-1f, 1f)
        if (!matrix.isIdentity) {
            val transformed = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            if (transformed !== bitmap) {
                bitmap.recycle()
                bitmap = transformed
            }
        }

        // Face rect arrives in upright, non-mirrored coordinates.
        var face = args.faceRect?.takeIf { it.width > 0.0 && it.height > 0.0 }
        if (face != null && args.mirror) face = face.mirrored()

        var cropApplied = false
        if (face != null) {
            val crop = computeCropRect(bitmap.width, bitmap.height, face, args.marginFactor, args.aspectRatio)
            if (crop.width < bitmap.width || crop.height < bitmap.height) {
                val cropped = Bitmap.createBitmap(bitmap, crop.left, crop.top, crop.width, crop.height)
                if (cropped !== bitmap) {
                    bitmap.recycle()
                    bitmap = cropped
                }
                cropApplied = true
            }
        }

        val shortSide = min(bitmap.width, bitmap.height)
        if (args.targetShortSide > 0 && shortSide > args.targetShortSide) {
            val scale = args.targetShortSide.toDouble() / shortSide
            val nw = (bitmap.width * scale).roundToInt().coerceAtLeast(1)
            val nh = (bitmap.height * scale).roundToInt().coerceAtLeast(1)
            val scaled = Bitmap.createScaledBitmap(bitmap, nw, nh, true)
            if (scaled !== bitmap) {
                bitmap.recycle()
                bitmap = scaled
            }
        }

        val dir = args.outputDir?.takeIf { it.isNotBlank() }?.let { File(it) } ?: context.cacheDir
        dir.mkdirs()
        val output = File(dir, "$FILE_PREFIX${System.currentTimeMillis()}.jpg")
        FileOutputStream(output).use { stream ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, args.jpegQuality.coerceIn(1, 100), stream)
        }

        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        bitmap.recycle()
        val luma = QualityMetrics.lumaFromArgb(pixels)
        val brightness = QualityMetrics.brightness(luma, width, height)
        // After a crop the whole image is the face region; otherwise measure
        // the face area (or the centre when no face was given).
        val sharpnessRegion = if (cropApplied || face == null) {
            null
        } else {
            PixelRect(
                (face.left * width).roundToInt(),
                (face.top * height).roundToInt(),
                (face.width * width).roundToInt(),
                (face.height * height).roundToInt(),
            )
        }
        val sharpness = QualityMetrics.sharpness(luma, width, height, sharpnessRegion)

        return mapOf(
            "path" to output.absolutePath,
            "width" to width,
            "height" to height,
            "brightness" to brightness,
            "sharpness" to sharpness,
            "cropApplied" to cropApplied,
        )
    }
}
