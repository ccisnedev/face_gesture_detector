package dev.macss.face_gesture_detector

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.Executors

/**
 * Flutter plugin that processes camera frames through MediaPipe Face Landmarker
 * and emits FaceFrame maps to Dart via EventChannel.
 *
 * Data flow:
 *   processFrame() → SingleSlotFrameBuffer → background executor →
 *   FrameDecoder → FaceLandmarkerEngine → FaceFrameStreamHandler → Dart
 */
class FaceGestureDetectorPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var applicationContext: Context

    private val streamHandler = FaceFrameStreamHandler()
    private val frameBuffer = SingleSlotFrameBuffer<RawFrame>()

    private var engine: FaceLandmarkerEngine? = null
    private var backgroundExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isRunning = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, "face_gesture_detector")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "face_gesture_detector/frames")
        eventChannel.setStreamHandler(streamHandler)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "startDetection" -> handleStartDetection(call, result)
            "stopDetection" -> handleStopDetection(result)
            "processFrame" -> handleProcessFrame(call, result)
            "processCapturedPhoto" -> handleProcessCapturedPhoto(call, result)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopEngine()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    private fun handleStartDetection(call: MethodCall, result: Result) {
        val confidence = (call.argument<Double>("faceDetectionConfidence") ?: 0.5).toFloat()
        val includeLandmarks = call.argument<Boolean>("includeLandmarks") ?: false

        engine = FaceLandmarkerEngine(applicationContext) { frameMap ->
            streamHandler.emit(frameMap)
        }
        engine?.initialize(confidence, includeLandmarks)
        isRunning = true

        result.success(null)
    }

    private fun handleStopDetection(result: Result) {
        stopEngine()
        result.success(null)
    }

    /**
     * Receives a raw camera frame from Dart, deposits it in the buffer,
     * and kicks off background decoding + inference.
     *
     * The buffer drops older frames if inference is still processing,
     * preventing backpressure buildup from 30fps camera input.
     */
    private fun handleProcessFrame(call: MethodCall, result: Result) {
        if (!isRunning) {
            result.success(null)
            return
        }

        val bytes = call.argument<ByteArray>("bytes")
        val width = call.argument<Int>("width")
        val height = call.argument<Int>("height")

        if (bytes == null || width == null || height == null) {
            result.success(null)
            return
        }

        val timestamp = call.argument<Long>("timestamp") ?: System.currentTimeMillis()
        val rotation = call.argument<Int>("rotation") ?: 0

        frameBuffer.deposit(RawFrame(bytes, width, height, timestamp, rotation))
        scheduleProcessing()

        // Return immediately — processing happens on the background executor.
        result.success(null)
    }

    /** Submits a task to drain the buffer and process the latest frame. */
    private fun scheduleProcessing() {
        backgroundExecutor.submit {
            val rawFrame = frameBuffer.acquire() ?: return@submit
            val mpImage = FrameDecoder.decode(rawFrame.bytes, rawFrame.width, rawFrame.height)
            // The NV21 bytes travel with the frame so the engine can measure
            // brightness/sharpness on the exact frame the result belongs to.
            engine?.detectAsync(
                mpImage, rawFrame.timestampMs, rawFrame.rotation,
                rawFrame.bytes, rawFrame.width, rawFrame.height,
            )
        }
    }

    /**
     * Post-processes a JPEG taken with `CameraController.takePicture()`:
     * EXIF orientation, optional mirror, crop around the face, downscale,
     * re-encode and quality metrics. Runs on the background executor and
     * answers on the main thread.
     */
    private fun handleProcessCapturedPhoto(call: MethodCall, result: Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "path is required", null)
            return
        }

        val faceRectMap = call.argument<Map<String, Any?>>("faceRect")
        val faceRect = faceRectMap?.let { map ->
            NormalizedRect(
                left = (map["left"] as? Number)?.toDouble() ?: 0.0,
                top = (map["top"] as? Number)?.toDouble() ?: 0.0,
                width = (map["width"] as? Number)?.toDouble() ?: 0.0,
                height = (map["height"] as? Number)?.toDouble() ?: 0.0,
            )
        }

        val args = CaptureProcessingArgs(
            path = path,
            mirror = call.argument<Boolean>("mirror") ?: false,
            faceRect = faceRect,
            marginFactor = (call.argument<Number>("marginFactor") ?: 0.6).toDouble(),
            aspectRatio = call.argument<Number>("aspectRatio")?.toDouble(),
            targetShortSide = call.argument<Int>("targetShortSide") ?: 1080,
            jpegQuality = call.argument<Int>("jpegQuality") ?: 92,
            outputDir = call.argument<String>("outputDir"),
        )

        backgroundExecutor.submit {
            try {
                val map = PhotoProcessor.process(applicationContext, args)
                mainHandler.post { result.success(map) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("PROCESSING_FAILED", e.message ?: e.javaClass.simpleName, null)
                }
            }
        }
    }

    private fun stopEngine() {
        isRunning = false
        engine?.close()
        engine = null
    }
}

/**
 * Raw camera frame data received from Dart's processFrame call.
 *
 * Stored in [SingleSlotFrameBuffer] until the background executor
 * picks it up for decoding and inference.
 */
private data class RawFrame(
    val bytes: ByteArray,
    val width: Int,
    val height: Int,
    val timestampMs: Long,
    val rotation: Int,
)
