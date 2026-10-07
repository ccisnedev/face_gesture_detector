import 'package:face_gesture_detector/src/configuration/face_gesture_configuration.dart';
import 'package:face_gesture_detector/src/model/details/capture_ready_details.dart';
import 'package:face_gesture_detector/src/model/face_blendshape.dart';
import 'package:face_gesture_detector/src/model/face_frame.dart';
import 'package:face_gesture_detector/src/recognizer/face_gesture_recognizer.dart';

/// Callback when every capture gate has held for the sustained duration.
typedef CaptureReadyCallback = void Function(CaptureReadyDetails details);

/// Callback when the set of blocking reasons changes.
typedef CaptureBlockedCallback = void Function(CaptureBlockedDetails details);

/// Evaluates the capture gates (face present, frontal pose, distance,
/// brightness, sharpness, eyes open, mouth closed) on every frame.
///
/// Emits [onCaptureBlocked] whenever the set of failing gates changes —
/// including the transition to an empty set, which means "all gates pass,
/// hold still" — and [onCaptureReady] once, when the gates have been
/// continuously satisfied for `captureSustainedDuration`. A new ready
/// event requires the gates to fail and pass again (a new episode).
class CaptureReadyRecognizer extends FaceGestureRecognizer {
  final CaptureReadyCallback onCaptureReady;
  final CaptureBlockedCallback onCaptureBlocked;

  Duration? _clearSince;
  bool _readyFired = false;
  List<CaptureBlockReason>? _lastReasons;

  CaptureReadyRecognizer({
    required FaceGestureConfiguration configuration,
    required this.onCaptureReady,
    required this.onCaptureBlocked,
  }) : super(configuration);

  @override
  void addFaceFrame(FaceFrame frame) {
    final reasons = evaluate(frame);

    if (!_sameReasons(reasons, _lastReasons)) {
      _lastReasons = reasons;
      onCaptureBlocked(CaptureBlockedDetails(reasons: reasons, frame: frame));
    }

    if (reasons.isNotEmpty) {
      _clearSince = null;
      _readyFired = false;
      return;
    }

    _clearSince ??= frame.timestamp;
    final sustained = frame.timestamp - _clearSince!;
    if (!_readyFired && sustained >= configuration.captureSustainedDuration) {
      _readyFired = true;
      onCaptureReady(CaptureReadyDetails(frame: frame, sustainedFor: sustained));
    }
  }

  /// Returns the gates that [frame] fails, in enum order. Pure — exposed
  /// so apps can evaluate a frame without a recognizer instance.
  List<CaptureBlockReason> evaluate(FaceFrame frame) {
    final reasons = <CaptureBlockReason>[];
    final cfg = configuration;

    if (!frame.isFaceDetected) {
      reasons.add(CaptureBlockReason.noFace);
      _addBrightnessReasons(frame, reasons);
      return reasons;
    }

    if (cfg.captureRequireFrontal) {
      final pose = frame.poseAngles;
      if (pose.yaw.abs() > cfg.captureMaxYaw ||
          pose.pitch.abs() > cfg.captureMaxPitch) {
        reasons.add(CaptureBlockReason.notFrontal);
      }
    }

    if (cfg.captureRequireOptimalDistance) {
      final ratio = _boundingBoxRatio(frame);
      if (ratio != null) {
        if (ratio < cfg.minDistanceRatio) {
          reasons.add(CaptureBlockReason.tooFar);
        } else if (ratio > cfg.maxDistanceRatio) {
          reasons.add(CaptureBlockReason.tooClose);
        }
      }
    }

    _addBrightnessReasons(frame, reasons);

    if (frame.quality.sharpness < cfg.captureMinSharpness) {
      reasons.add(CaptureBlockReason.blurry);
    }

    if (cfg.captureRequireEyesOpen) {
      final left = frame.blendshapes[FaceBlendshape.eyeBlinkLeft] ?? 0.0;
      final right = frame.blendshapes[FaceBlendshape.eyeBlinkRight] ?? 0.0;
      if (left >= cfg.blinkThreshold || right >= cfg.blinkThreshold) {
        reasons.add(CaptureBlockReason.eyesClosed);
      }
    }

    if (cfg.captureRequireMouthClosed) {
      final jaw = frame.blendshapes[FaceBlendshape.jawOpen] ?? 0.0;
      if (jaw >= cfg.mouthOpenThreshold) {
        reasons.add(CaptureBlockReason.mouthOpen);
      }
    }

    return reasons;
  }

  void _addBrightnessReasons(FaceFrame frame, List<CaptureBlockReason> out) {
    final b = frame.quality.brightness;
    if (b < configuration.captureMinBrightness) {
      out.add(CaptureBlockReason.tooDark);
    } else if (b > configuration.captureMaxBrightness) {
      out.add(CaptureBlockReason.tooBright);
    }
  }

  /// Face area over frame area, or `null` when the frame size is unknown.
  double? _boundingBoxRatio(FaceFrame frame) {
    if (frame.frameWidth <= 0 || frame.frameHeight <= 0) return null;
    final frameArea = frame.frameWidth * frame.frameHeight;
    final box = frame.faceBoundingBox;
    return (box.width * box.height) / frameArea;
  }

  static bool _sameReasons(
    List<CaptureBlockReason> a,
    List<CaptureBlockReason>? b,
  ) {
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void reset() {
    _clearSince = null;
    _readyFired = false;
    _lastReasons = null;
  }

  @override
  void dispose() {
    // No resources to release.
  }
}
