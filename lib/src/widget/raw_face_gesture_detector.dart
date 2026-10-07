import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../configuration/face_gesture_configuration.dart';
import '../controller/face_gesture_detector_controller.dart';
import '../model/captured_photo.dart';
import '../model/face_frame.dart';
import '../platform/face_detection_options.dart';
import '../platform/face_gesture_detector_platform_interface.dart';
import '../util/rect_mapping.dart';
import 'camera_capture_adapter.dart';
import 'package:face_gesture_detector/src/recognizer/face_gesture_recognizer.dart';
import 'package:face_gesture_detector/src/recognizer/face_gesture_recognizer_factory.dart';

/// Layer 2 widget that manages the recognizer lifecycle and frame dispatch.
///
/// Analogous to [RawGestureDetector] in Flutter's gesture system.
/// Accepts a [recognizers] map for advanced use cases. Most developers
/// should use [FaceGestureDetector] (Layer 1 facade) instead.
///
/// When [cameraController] is provided, the widget manages the full pipeline:
/// starts native detection, subscribes to the camera image stream, sends frames
/// to native for processing, and dispatches the resulting [FaceFrame]s to all
/// active recognizers. It also acts as the [FaceCaptureHost] of the
/// [controller], enabling [FaceGestureDetectorController.capturePhoto].
///
/// When [cameraController] is null (e.g. in tests), frames can be dispatched
/// manually via [RawFaceGestureDetectorState.dispatchFrame].
class RawFaceGestureDetector extends StatefulWidget {
  /// Map of recognizer Type to factory. Each factory creates one recognizer.
  final Map<Type, FaceGestureRecognizerFactory> recognizers;

  /// Configuration forwarded to recognizers.
  final FaceGestureConfiguration configuration;

  /// Optional controller for imperative pause/resume/reset/capture.
  final FaceGestureDetectorController? controller;

  /// Camera controller that provides the image stream.
  ///
  /// Must be initialized before this widget mounts. The widget subscribes
  /// to [CameraController.startImageStream] and sends frames to the native
  /// layer via [FaceGestureDetectorPlatform.processFrame]. Frames must be
  /// delivered as NV21 (`imageFormatGroup: ImageFormatGroup.nv21`).
  final CameraController? cameraController;

  /// Child widget, typically a camera preview.
  final Widget? child;

  const RawFaceGestureDetector({
    super.key,
    required this.recognizers,
    required this.configuration,
    this.controller,
    this.cameraController,
    this.child,
  });

  @override
  State<RawFaceGestureDetector> createState() => RawFaceGestureDetectorState();
}

/// Public state so tests and advanced users can call [dispatchFrame].
class RawFaceGestureDetectorState extends State<RawFaceGestureDetector>
    implements FaceCaptureHost {
  final Map<Type, FaceGestureRecognizer> _activeRecognizers = {};
  int _frameCounter = 0;
  StreamSubscription<Map<String, dynamic>>? _frameStreamSubscription;
  bool _isStreaming = false;
  bool _isCapturing = false;

  FaceFrame? _lastFrame;
  int _lastImageWidth = 0;
  int _lastImageHeight = 0;

  /// Overrides the camera used by [capturePhoto]. Testing only.
  @visibleForTesting
  CameraCaptureAdapter? debugCaptureAdapter;

  FaceGestureDetectorPlatform get _platform =>
      FaceGestureDetectorPlatform.instance;

  @override
  FaceFrame? get lastFrame => _lastFrame;

  /// Whether the widget is currently subscribed to the camera image stream.
  bool get isStreaming => _isStreaming;

  @override
  void initState() {
    super.initState();
    _syncRecognizers(widget.recognizers);
    widget.controller?.addListener(_onControllerChanged);
    widget.controller?.attach(this);
    if (widget.cameraController != null) {
      _startPipeline();
    }
  }

  @override
  void didUpdateWidget(covariant RawFaceGestureDetector oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      oldWidget.controller?.detach(this);
      widget.controller?.addListener(_onControllerChanged);
      widget.controller?.attach(this);
    }

    if (!_mapsEqual(oldWidget.recognizers, widget.recognizers)) {
      _syncRecognizers(widget.recognizers);
    }

    if (oldWidget.cameraController != widget.cameraController) {
      _stopPipeline();
      if (widget.cameraController != null) {
        _startPipeline();
      }
    }
  }

  @override
  void dispose() {
    _stopPipeline();
    widget.controller?.removeListener(_onControllerChanged);
    widget.controller?.detach(this);
    for (final recognizer in _activeRecognizers.values) {
      recognizer.dispose();
    }
    _activeRecognizers.clear();
    super.dispose();
  }

  /// Starts the full native detection pipeline.
  Future<void> _startPipeline() async {
    final config = widget.configuration;
    final options = FaceDetectionOptions.fromConfiguration(config);

    await _platform.startDetection(options);

    _frameStreamSubscription = _platform.faceFrameStream.listen(
      _onNativeFaceFrame,
    );

    final camera = widget.cameraController!;
    if (camera.value.isInitialized && !_isStreaming) {
      await camera.startImageStream(_onCameraImage);
      _isStreaming = true;
    }
  }

  /// Stops the native detection pipeline and cleans up subscriptions.
  Future<void> _stopPipeline() async {
    if (_isStreaming) {
      try {
        await widget.cameraController?.stopImageStream();
      } catch (_) {
        // Camera may already be disposed.
      }
      _isStreaming = false;
    }

    await _frameStreamSubscription?.cancel();
    _frameStreamSubscription = null;

    try {
      await _platform.stopDetection();
    } catch (_) {
      // Plugin may not be initialized.
    }
  }

  /// Handles a raw camera image from [CameraController.startImageStream].
  ///
  /// Concatenates YUV420 planes into a single byte buffer and sends it
  /// to the native layer for MediaPipe processing.
  void _onCameraImage(CameraImage image) {
    _lastImageWidth = image.width;
    _lastImageHeight = image.height;

    if (_isCapturing || (widget.controller?.isPaused ?? false)) return;

    final bytes = _concatenatePlanes(image.planes);
    final rotation =
        widget.cameraController?.description.sensorOrientation ?? 0;

    _platform.processFrame(
      FrameData(
        bytes: bytes,
        width: image.width,
        height: image.height,
        rotation: rotation,
      ),
    );
  }

  /// Handles a deserialized face frame map from the native EventChannel.
  void _onNativeFaceFrame(Map<String, dynamic> map) {
    final frame = FaceFrame.fromMap(map);
    dispatchFrame(frame);
  }

  /// Concatenates all image planes into a single [Uint8List].
  static Uint8List _concatenatePlanes(List<Plane> planes) {
    int totalLength = 0;
    for (final plane in planes) {
      totalLength += plane.bytes.length;
    }
    final result = Uint8List(totalLength);
    int offset = 0;
    for (final plane in planes) {
      result.setRange(offset, offset + plane.bytes.length, plane.bytes);
      offset += plane.bytes.length;
    }
    return result;
  }

  /// Dispatches a [FaceFrame] to all active recognizers.
  ///
  /// Called internally when native frames arrive, or externally for testing.
  /// The frame is remembered as [lastFrame] even when dispatch is paused,
  /// so a capture always uses the most recent face box.
  void dispatchFrame(FaceFrame frame) {
    _lastFrame = frame;

    if (_isCapturing || (widget.controller?.isPaused ?? false)) return;

    // Frame skipping: process 1 out of every (skipCount + 1) frames.
    final skipCount = widget.configuration.frameSkipCount;
    if (skipCount > 0) {
      if (_frameCounter % (skipCount + 1) != 0) {
        _frameCounter++;
        return;
      }
      _frameCounter++;
    }

    for (final recognizer in _activeRecognizers.values) {
      recognizer.addFaceFrame(frame);
    }
  }

  // ── Photo capture ─────────────────────────────────────────────

  /// Takes a picture with the camera and post-processes it natively.
  ///
  /// Prefer [FaceGestureDetectorController.capturePhoto], which guards
  /// against concurrent captures. Frame dispatch is suspended while the
  /// picture is taken; when [CaptureOptions.stopStreamWhileCapturing] is
  /// set the image stream is stopped before `takePicture()` and restarted
  /// afterwards, even if the capture fails.
  @override
  Future<CapturedPhoto> capturePhoto(CaptureOptions options) async {
    final adapter = debugCaptureAdapter ??
        (widget.cameraController != null
            ? CameraControllerCaptureAdapter(widget.cameraController!)
            : null);
    if (adapter == null) {
      throw StateError('capturePhoto() requires a cameraController.');
    }
    if (!adapter.isInitialized) {
      throw StateError('The camera is not initialized.');
    }

    final frame = _lastFrame;
    final sensorOrientation = adapter.sensorOrientation;
    final restartStream = options.stopStreamWhileCapturing && _isStreaming;

    _isCapturing = true;
    String path;
    try {
      if (restartStream) {
        await adapter.stopImageStream();
        _isStreaming = false;
      }
      path = await adapter.takePicture().timeout(options.timeout);
    } finally {
      if (restartStream && !_isStreaming && mounted) {
        try {
          await adapter.startImageStream(_onCameraImage);
          _isStreaming = true;
        } catch (_) {
          // Camera may have been disposed while capturing.
        }
      }
      _isCapturing = false;
    }

    Rect? faceRect;
    if (options.cropToFace && frame != null && frame.isFaceDetected) {
      final w = frame.frameWidth > 0 ? frame.frameWidth : _lastImageWidth;
      final h = frame.frameHeight > 0 ? frame.frameHeight : _lastImageHeight;
      if (w > 0 && h > 0) {
        final box = frame.faceBoundingBox;
        final normalized = Rect.fromLTWH(
          box.left / w,
          box.top / h,
          box.width / w,
          box.height / h,
        );
        faceRect = mapSensorRectToUpright(normalized, sensorOrientation);
      }
    }

    final capturedAt = DateTime.now();
    final reply = await _platform
        .processCapturedPhoto(options.toPlatformMap(path: path, faceRect: faceRect))
        .timeout(options.timeout);
    return CapturedPhoto.fromPlatformMap(
      reply,
      faceRect: faceRect,
      pose: frame?.poseAngles,
      capturedAt: capturedAt,
    );
  }

  // ── Controller / recognizers ──────────────────────────────────

  void _onControllerChanged() {
    if (widget.controller?.isPaused ?? false) return;

    // If not paused, this is a reset signal.
    for (final recognizer in _activeRecognizers.values) {
      recognizer.reset();
    }
  }

  /// Syncs the active recognizer instances with the requested map.
  ///
  /// Disposes removed recognizers, creates new ones, reuses persisting.
  void _syncRecognizers(Map<Type, FaceGestureRecognizerFactory> requested) {
    // Dispose recognizers no longer in the map.
    final removedKeys = _activeRecognizers.keys
        .where((k) => !requested.containsKey(k))
        .toList();
    for (final key in removedKeys) {
      _activeRecognizers.remove(key)?.dispose();
    }

    // Create recognizers that are new.
    for (final entry in requested.entries) {
      if (!_activeRecognizers.containsKey(entry.key)) {
        _activeRecognizers[entry.key] = entry.value.create();
      }
    }
  }

  bool _mapsEqual(
    Map<Type, FaceGestureRecognizerFactory> a,
    Map<Type, FaceGestureRecognizerFactory> b,
  ) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child ?? const SizedBox.shrink();
  }
}
