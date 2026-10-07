import 'dart:ui';

import 'package:face_gesture_detector/src/model/image_quality_metrics.dart';
import 'package:face_gesture_detector/src/model/pose_angles.dart';

/// Options for [FaceGestureDetectorController.capturePhoto].
class CaptureOptions {
  /// Mirror the photo horizontally (selfie look). Off by default: for
  /// biometric use the photo should keep the real (non-mirrored) geometry.
  final bool mirror;

  /// Crop the photo around the last detected face. When no face is known
  /// the full frame is kept.
  final bool cropToFace;

  /// Extra room around the face box, as a fraction of its size
  /// (0.6 = 60 % wider and taller than the detected box).
  final double marginFactor;

  /// Width / height of the crop. `0.75` is a 3:4 portrait; `null` keeps
  /// the expanded face box as is.
  final double? aspectRatio;

  /// The output is downscaled so that its short side does not exceed this
  /// value. It is never upscaled. `0` disables downscaling.
  final int targetShortSide;

  /// JPEG quality, 1–100.
  final int jpegQuality;

  /// Directory for the output file. Defaults to the app cache directory.
  final String? outputDir;

  /// Stop the analysis image stream while `takePicture()` runs and restart
  /// it afterwards. Safer across camera implementations; set to `false`
  /// only after verifying the device captures fine while streaming.
  final bool stopStreamWhileCapturing;

  /// Upper bound for `takePicture()` and for the native post-processing,
  /// each. A camera whose preview surface went away (screen off, app in
  /// background) may never answer `takePicture()`; the timeout turns that
  /// into a [TimeoutException] and lets the image stream restart.
  final Duration timeout;

  const CaptureOptions({
    this.mirror = false,
    this.cropToFace = true,
    this.marginFactor = 0.6,
    this.aspectRatio = 0.75,
    this.targetShortSide = 1080,
    this.jpegQuality = 92,
    this.outputDir,
    this.stopStreamWhileCapturing = true,
    this.timeout = const Duration(seconds: 10),
  });

  /// Serializes the fields consumed by the native processor.
  Map<String, dynamic> toPlatformMap({required String path, Rect? faceRect}) {
    return {
      'path': path,
      'mirror': mirror,
      'faceRect': faceRect == null
          ? null
          : {
              'left': faceRect.left,
              'top': faceRect.top,
              'width': faceRect.width,
              'height': faceRect.height,
            },
      'marginFactor': marginFactor,
      'aspectRatio': aspectRatio,
      'targetShortSide': targetShortSide,
      'jpegQuality': jpegQuality,
      'outputDir': outputDir,
    };
  }
}

/// A photo captured through [FaceGestureDetectorController.capturePhoto].
class CapturedPhoto {
  /// Absolute path of the processed JPEG.
  final String path;

  /// Dimensions of the processed JPEG in pixels.
  final int width;
  final int height;

  /// Face box used for the crop, normalized (0..1) to the upright,
  /// non-mirrored full frame. `null` when no face was known at capture.
  final Rect? faceRect;

  /// Head pose of the last analysed frame before the capture, if any.
  final PoseAngles? pose;

  /// Quality metrics measured on the processed JPEG.
  final ImageQualityMetrics quality;

  /// Whether the output was cropped around the face.
  final bool cropApplied;

  /// Wall-clock time of the capture.
  final DateTime capturedAt;

  const CapturedPhoto({
    required this.path,
    required this.width,
    required this.height,
    required this.faceRect,
    required this.pose,
    required this.quality,
    required this.cropApplied,
    required this.capturedAt,
  });

  /// Builds the result from the native `processCapturedPhoto` reply.
  factory CapturedPhoto.fromPlatformMap(
    Map<String, dynamic> map, {
    Rect? faceRect,
    PoseAngles? pose,
    DateTime? capturedAt,
  }) {
    return CapturedPhoto(
      path: map['path'] as String,
      width: (map['width'] as num).toInt(),
      height: (map['height'] as num).toInt(),
      faceRect: faceRect,
      pose: pose,
      quality: ImageQualityMetrics(
        brightness: (map['brightness'] as num?)?.toDouble() ?? 0.0,
        sharpness: (map['sharpness'] as num?)?.toDouble() ?? 0.0,
      ),
      cropApplied: map['cropApplied'] as bool? ?? false,
      capturedAt: capturedAt ?? DateTime.now(),
    );
  }
}
