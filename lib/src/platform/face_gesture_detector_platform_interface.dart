import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:face_gesture_detector/src/platform/face_detection_options.dart';
import 'package:face_gesture_detector/src/platform/method_channel_face_gesture_detector.dart';

/// The platform interface for face gesture detection.
///
/// Defines the Dart↔Native contract that platform-specific implementations
/// must fulfill. Uses [PlatformInterface] for token verification to prevent
/// accidental direct implementation (should extend, not implement).
abstract class FaceGestureDetectorPlatform extends PlatformInterface {
  FaceGestureDetectorPlatform() : super(token: _token);

  static final Object _token = Object();

  static FaceGestureDetectorPlatform _instance =
      MethodChannelFaceGestureDetector();

  /// The current platform implementation.
  ///
  /// Defaults to [MethodChannelFaceGestureDetector].
  static FaceGestureDetectorPlatform get instance => _instance;

  /// Override the default platform implementation (for testing or federation).
  static set instance(FaceGestureDetectorPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Initializes the native face detection engine with the given [options].
  ///
  /// On Android: starts MediaPipe FaceLandmarker with GPU delegate.
  Future<void> startDetection(FaceDetectionOptions options) {
    throw UnimplementedError('startDetection() has not been implemented.');
  }

  /// Stops the native face detection engine and releases resources.
  Future<void> stopDetection() {
    throw UnimplementedError('stopDetection() has not been implemented.');
  }

  /// Sends a raw camera frame to the native pipeline for processing.
  ///
  /// Non-blocking on the native side — the frame is deposited in a
  /// single-slot buffer and picked up by a background thread.
  Future<void> processFrame(FrameData frameData) {
    throw UnimplementedError('processFrame() has not been implemented.');
  }

  /// Stream of face frame maps emitted by the native pipeline.
  ///
  /// Each map is deserialized into a [FaceFrame] on the Dart side.
  Stream<Map<String, dynamic>> get faceFrameStream {
    throw UnimplementedError('faceFrameStream has not been implemented.');
  }

  /// Post-processes a JPEG produced by `CameraController.takePicture()`:
  /// applies EXIF orientation, optional mirroring, crops around the face,
  /// downscales, re-encodes and measures quality.
  ///
  /// [args] is built by `CaptureOptions.toPlatformMap`. The reply contains
  /// `path`, `width`, `height`, `brightness`, `sharpness`, `cropApplied`
  /// (see `CapturedPhoto.fromPlatformMap`).
  Future<Map<String, dynamic>> processCapturedPhoto(Map<String, dynamic> args) {
    throw UnimplementedError('processCapturedPhoto() has not been implemented.');
  }
}
