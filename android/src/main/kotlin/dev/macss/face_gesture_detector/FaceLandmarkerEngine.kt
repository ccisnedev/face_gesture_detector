package dev.macss.face_gesture_detector

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import com.google.mediapipe.framework.image.MPImage

/**
 * Manages the MediaPipe FaceLandmarker lifecycle and converts detection
 * results into the map format expected by [FaceFrame.fromMap] in Dart.
 *
 * Runs in LIVE_STREAM mode with GPU delegate (CPU fallback).
 * Thread safety: [detectAsync] must be called from a single thread.
 * Results arrive via the [onResult] callback provided at construction.
 */
class FaceLandmarkerEngine(
    private val context: Context,
    private val onResult: (Map<String, Any?>) -> Unit,
) {

    companion object {
        private const val TAG = "FaceLandmarkerEngine"
        private const val MODEL_ASSET = "models/face_landmarker.task"
        private const val MAX_PENDING_FRAMES = 4
    }

    /** Y plane of an NV21 frame (stride == width) with its dimensions. */
    private class LumaPlane(val bytes: ByteArray, val width: Int, val height: Int)

    private var landmarker: FaceLandmarker? = null
    private var includeLandmarks = false
    @Volatile private var currentRotation: Int = 0

    /**
     * Luminance planes of the frames currently in flight, keyed by the
     * timestamp passed to [detectAsync]. MediaPipe echoes that timestamp in
     * the result, which lets [handleResult] compute quality metrics on the
     * exact frame the landmarks came from. Bounded so a dropped result can
     * never leak memory.
     */
    private val pendingLuma = object : LinkedHashMap<Long, LumaPlane>(8, 0.75f, false) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Long, LumaPlane>?): Boolean =
            size > MAX_PENDING_FRAMES
    }
    private val pendingLock = Any()

    /**
     * Initializes the FaceLandmarker with the given detection options.
     *
     * @param faceDetectionConfidence Minimum confidence score for face detection.
     * @param outputLandmarks Whether to include the 478 landmarks in the result map.
     */
    fun initialize(faceDetectionConfidence: Float, outputLandmarks: Boolean) {
        includeLandmarks = outputLandmarks

        val baseOptions = BaseOptions.builder()
            .setModelAssetPath(MODEL_ASSET)
            .setDelegate(Delegate.GPU)
            .build()

        val options = FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(com.google.mediapipe.tasks.vision.core.RunningMode.LIVE_STREAM)
            .setNumFaces(1)
            .setMinFaceDetectionConfidence(faceDetectionConfidence)
            .setMinFacePresenceConfidence(faceDetectionConfidence)
            .setMinTrackingConfidence(faceDetectionConfidence)
            .setOutputFaceBlendshapes(true)
            .setOutputFacialTransformationMatrixes(true)
            .setResultListener(::handleResult)
            .setErrorListener { error ->
                Log.e(TAG, "MediaPipe FaceLandmarker error", error)
            }
            .build()

        landmarker = FaceLandmarker.createFromOptions(context, options)
    }

    /**
     * Sends a frame to the FaceLandmarker for asynchronous processing.
     *
     * Non-blocking. Results arrive via the [onResult] callback passed during
     * construction. If a previous frame is still being processed, MediaPipe
     * drops the new one automatically (LIVE_STREAM mode behavior).
     */
    fun detectAsync(image: MPImage, timestampMs: Long, rotation: Int = 0) {
        currentRotation = rotation
        landmarker?.detectAsync(image, timestampMs)
    }

    /**
     * Same as [detectAsync], additionally keeping the NV21 bytes of the
     * frame so that brightness and sharpness can be measured on it when
     * the result arrives. [nv21] must hold at least `width * height` bytes
     * (the Y plane comes first in NV21).
     */
    fun detectAsync(
        image: MPImage,
        timestampMs: Long,
        rotation: Int,
        nv21: ByteArray,
        width: Int,
        height: Int,
    ) {
        if (nv21.size >= width * height) {
            synchronized(pendingLock) {
                pendingLuma[timestampMs] = LumaPlane(nv21, width, height)
            }
        }
        detectAsync(image, timestampMs, rotation)
    }

    /** Releases the FaceLandmarker and all associated native resources. */
    fun close() {
        landmarker?.close()
        landmarker = null
        synchronized(pendingLock) { pendingLuma.clear() }
    }

    private fun takeLuma(timestampMs: Long): LumaPlane? =
        synchronized(pendingLock) { pendingLuma.remove(timestampMs) }

    /**
     * Brightness of the whole frame and sharpness of [region] (face box in
     * frame pixels, or the centre when null). Returns null when the frame
     * bytes are not available (legacy [detectAsync] overload).
     */
    private fun computeQuality(luma: LumaPlane?, region: PixelRect?): Pair<Double, Double>? {
        if (luma == null) return null
        val brightness = QualityMetrics.brightness(luma.bytes, luma.width, luma.height)
        val sharpness = QualityMetrics.sharpness(luma.bytes, luma.width, luma.height, region)
        return brightness to sharpness
    }

    /**
     * Converts a MediaPipe [FaceLandmarkerResult] into the map format
     * expected by [FaceFrame.fromMap] in Dart.
     *
     * Map keys match the Dart deserialization contract exactly:
     *   timestamp, isFaceDetected, faceConfidence, faceBoundingBox,
     *   poseAngles, blendshapes, landmarks (optional), quality
     */
    private fun handleResult(result: FaceLandmarkerResult, input: MPImage) {
        val faceLandmarks = result.faceLandmarks()
        val isFaceDetected = faceLandmarks.isNotEmpty()
        val luma = takeLuma(result.timestampMs())

        val frameMap = if (!isFaceDetected) {
            buildNoFaceMap(result.timestampMs(), input, luma)
        } else {
            buildFaceDetectedMap(result, input, luma)
        }

        onResult(frameMap)
    }

    private fun buildNoFaceMap(
        timestampMs: Long,
        input: MPImage,
        luma: LumaPlane?,
    ): Map<String, Any?> {
        val quality = computeQuality(luma, null)
        return mapOf(
            "timestamp" to timestampMs,
            "isFaceDetected" to false,
            "faceConfidence" to 0.0,
            "frameWidth" to input.width,
            "frameHeight" to input.height,
            "faceBoundingBox" to mapOf(
                "left" to 0.0, "top" to 0.0, "width" to 0.0, "height" to 0.0,
            ),
            "poseAngles" to mapOf("pitch" to 0.0, "yaw" to 0.0, "roll" to 0.0),
            "blendshapes" to emptyMap<String, Double>(),
            "landmarks" to null,
            "quality" to mapOf(
                "brightness" to (quality?.first ?: 0.0),
                "sharpness" to (quality?.second ?: 0.0),
            ),
        )
    }

    private fun buildFaceDetectedMap(
        result: FaceLandmarkerResult,
        input: MPImage,
        luma: LumaPlane?,
    ): Map<String, Any?> {
        val landmarks = result.faceLandmarks()[0]
        val blendshapes = result.faceBlendshapes().orElse(null)?.get(0)
        val matrix = result.facialTransformationMatrixes().orElse(null)?.get(0)

        // Bounding box from landmark extremes (normalized 0..1 → pixel coordinates)
        val imageWidth = input.width.toDouble()
        val imageHeight = input.height.toDouble()
        val xs = landmarks.map { it.x() * imageWidth }
        val ys = landmarks.map { it.y() * imageHeight }
        val minX = xs.min()
        val minY = ys.min()
        val maxX = xs.max()
        val maxY = ys.max()

        // Euler angles from the 4×4 transformation matrix
        val (rawPitch, rawYaw, rawRoll) = if (matrix != null) {
            // MediaPipe Matrix stores 16 floats in row-major order.
            // EulerAngleCalculator expects column-major, so we transpose.
            val flatMatrix = FloatArray(16)
            for (row in 0 until 4) {
                for (col in 0 until 4) {
                    flatMatrix[col * 4 + row] = matrix.get(row * 4 + col)
                }
            }
            EulerAngleCalculator.fromMatrix(flatMatrix)
        } else {
            Triple(0.0, 0.0, 0.0)
        }

        // MediaPipe computes angles in the raw image coordinate system.
        // Compensate for camera sensor orientation so angles are relative
        // to the device's portrait orientation.
        val (pitch, yaw, roll) = correctAnglesForRotation(
            rawPitch, rawYaw, rawRoll, currentRotation,
        )

        // Blendshape map: name → score
        val blendshapeMap = mutableMapOf<String, Double>()
        blendshapes?.forEach { category ->
            val name = category.categoryName()
            if (name != null) {
                blendshapeMap[name] = category.score().toDouble()
            }
        }

        // Landmarks list (optional, ~10KB when enabled)
        val landmarkList = if (includeLandmarks) {
            landmarks.map { lm ->
                mapOf(
                    "x" to lm.x().toDouble(),
                    "y" to lm.y().toDouble(),
                    "z" to lm.z().toDouble(),
                )
            }
        } else {
            null
        }

        // FaceLandmarkerResult does not expose the raw detection score.
        // If landmarks are present the face already passed the configured
        // minFaceDetectionConfidence threshold, so we report 1.0.
        val faceConfidence = 1.0

        // Brightness over the whole frame, sharpness inside the face box.
        val faceRegion = PixelRect(
            minX.toInt(), minY.toInt(),
            (maxX - minX).toInt().coerceAtLeast(1),
            (maxY - minY).toInt().coerceAtLeast(1),
        )
        val quality = computeQuality(luma, faceRegion)

        return mapOf(
            "timestamp" to result.timestampMs(),
            "isFaceDetected" to true,
            "faceConfidence" to faceConfidence,
            "frameWidth" to input.width,
            "frameHeight" to input.height,
            "faceBoundingBox" to mapOf(
                "left" to minX,
                "top" to minY,
                "width" to (maxX - minX),
                "height" to (maxY - minY),
            ),
            "poseAngles" to mapOf(
                "pitch" to pitch,
                "yaw" to yaw,
                "roll" to roll,
            ),
            "blendshapes" to blendshapeMap,
            "landmarks" to landmarkList,
            "quality" to mapOf(
                "brightness" to (quality?.first ?: 0.0),
                "sharpness" to (quality?.second ?: 0.0),
            ),
        )
    }

    /**
     * Transforms Euler angles from raw-image coordinates to device-portrait
     * coordinates, compensating for camera sensor orientation.
     *
     * The camera sensor produces frames rotated [sensorOrientation]° CW from
     * portrait. The image content is therefore (360 − sensorOrientation)° CW
     * from upright. Pitch and yaw (rotations around X/Y) are remapped using
     * the 2-D rotation inverse, and the roll offset is subtracted.
     */
    private fun correctAnglesForRotation(
        pitch: Double, yaw: Double, roll: Double, sensorOrientation: Int,
    ): Triple<Double, Double, Double> {
        val alpha = ((360 - sensorOrientation) % 360 + 360) % 360
        val (cp, cy, cr) = when (alpha) {
            90  -> Triple(-yaw, -pitch, roll - 90.0)
            180 -> Triple(-pitch, -yaw, roll - 180.0)
            270 -> Triple(yaw, pitch, roll - 270.0)
            else -> Triple(pitch, yaw, roll)
        }
        // Normalise roll to [−180, 180]
        var nr = cr % 360.0
        if (nr > 180.0) nr -= 360.0
        if (nr < -180.0) nr += 360.0
        return Triple(cp, cy, nr)
    }
}
