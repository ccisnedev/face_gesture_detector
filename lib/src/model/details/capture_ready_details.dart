import 'package:face_gesture_detector/src/model/face_frame.dart';

/// Why the current frame is not suitable for capturing a photo.
///
/// Emitted by the [CaptureReadyRecognizer] so the app can guide the user
/// ("look at the camera", "move closer", "more light", …).
enum CaptureBlockReason {
  /// No face is detected in the frame.
  noFace,

  /// Head yaw or pitch exceeds the configured frontal tolerance.
  notFrontal,

  /// The face occupies less than `minDistanceRatio` of the frame.
  tooFar,

  /// The face occupies more than `maxDistanceRatio` of the frame.
  tooClose,

  /// Frame brightness is below `captureMinBrightness`.
  tooDark,

  /// Frame brightness is above `captureMaxBrightness`.
  tooBright,

  /// Sharpness of the face region is below `captureMinSharpness`.
  blurry,

  /// One or both eyes are closed (blink blendshape above `blinkThreshold`).
  eyesClosed,

  /// The mouth is open (`jawOpen` above `mouthOpenThreshold`).
  mouthOpen,
}

/// Details emitted once all capture gates have been satisfied for the
/// configured `captureSustainedDuration`.
class CaptureReadyDetails {
  /// The frame that completed the sustained window.
  final FaceFrame frame;

  /// How long the gates have been continuously satisfied.
  final Duration sustainedFor;

  const CaptureReadyDetails({required this.frame, required this.sustainedFor});
}

/// Details emitted when the set of blocking reasons changes.
///
/// An empty [reasons] list means every gate is satisfied and the sustained
/// timer is running — the app can show "hold still" until
/// `onCaptureReady` fires.
class CaptureBlockedDetails {
  /// Current blocking reasons, in [CaptureBlockReason] declaration order.
  final List<CaptureBlockReason> reasons;

  /// The frame that produced this evaluation.
  final FaceFrame frame;

  const CaptureBlockedDetails({required this.reasons, required this.frame});

  /// Whether every gate is satisfied (timer running, not yet ready).
  bool get isClear => reasons.isEmpty;
}
