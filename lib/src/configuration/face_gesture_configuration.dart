/// Threshold and behavior configuration for the face gesture detector.
///
/// Default values are calibrated for standard liveness flows based on
/// thresholds documented in the face verification and PAD research literature.
/// Override individual values to tune detection sensitivity.
class FaceGestureConfiguration {
  // ── Detection ─────────────────────────────────────

  /// Minimum confidence to consider a face detected. Range: 0.0–1.0.
  final double faceDetectionConfidence;

  // ── Distance ──────────────────────────────────────

  /// Bounding box ratio below which the face is classified as too far.
  final double minDistanceRatio;

  /// Bounding box ratio above which the face is classified as too close.
  final double maxDistanceRatio;

  // ── Gesture thresholds ────────────────────────────

  /// Yaw angle (degrees) beyond which a head turn is recognized.
  final double headTurnYawThreshold;

  /// Pitch angle (degrees) beyond which a head nod is recognized.
  final double headNodPitchThreshold;

  /// Eye blink blendshape value below which the eye is considered closed.
  final double blinkThreshold;

  /// Average mouth smile blendshape value above which a smile is recognized.
  final double smileThreshold;

  /// browInnerUp blendshape value above which a brow raise is recognized.
  final double browRaisedThreshold;

  /// jawOpen blendshape value above which the mouth is considered open.
  final double mouthOpenThreshold;

  // ── Gesture temporality ───────────────────────────

  /// Duration a gesture must be sustained before the callback fires.
  final Duration sustainedGestureDuration;

  // ── Performance ───────────────────────────────────

  /// Number of native frames to skip between processed frames.
  /// 0 = process every frame, 2 = process 1 out of 3.
  final int frameSkipCount;

  /// Whether to include the full 478-landmark mesh in FaceFrame.
  /// Disabled by default to reduce memory (~8KB per frame).
  final bool includeLandmarks;

  // ── Capture gates (CaptureReadyRecognizer) ────────

  /// Require |yaw| ≤ [captureMaxYaw] and |pitch| ≤ [captureMaxPitch].
  final bool captureRequireFrontal;

  /// Maximum absolute yaw (degrees) accepted for capture.
  final double captureMaxYaw;

  /// Maximum absolute pitch (degrees) accepted for capture.
  final double captureMaxPitch;

  /// Require the face box ratio to lie within
  /// [minDistanceRatio]..[maxDistanceRatio].
  final bool captureRequireOptimalDistance;

  /// Minimum frame brightness (0..1) accepted for capture.
  final double captureMinBrightness;

  /// Maximum frame brightness (0..1) accepted for capture.
  final double captureMaxBrightness;

  /// Minimum Laplacian-variance sharpness of the face region accepted for
  /// capture. Measured natively on the NV21 Y plane, subsampled to ~160
  /// columns (see `QualityMetrics`).
  ///
  /// Reference values (Samsung A04 front camera, 2026-09): a texture-less
  /// scene (blank ceiling, no face) measures 8–40 on the live 720p/1080p
  /// stream and 55–120 on the processed photo of the same scene. Faces
  /// have not been measured yet; the default of 60 is **provisional** and
  /// must be calibrated on the target device matrix with real users.
  final double captureMinSharpness;

  /// Require both eyes open (blink blendshapes below [blinkThreshold]).
  final bool captureRequireEyesOpen;

  /// Require the mouth closed (`jawOpen` below [mouthOpenThreshold]).
  final bool captureRequireMouthClosed;

  /// How long every capture gate must hold before `onCaptureReady` fires.
  final Duration captureSustainedDuration;

  const FaceGestureConfiguration({
    this.faceDetectionConfidence = 0.5,
    this.minDistanceRatio = 0.05,
    this.maxDistanceRatio = 0.40,
    this.headTurnYawThreshold = 25.0,
    this.headNodPitchThreshold = 20.0,
    this.blinkThreshold = 0.35,
    this.smileThreshold = 0.5,
    this.browRaisedThreshold = 0.5,
    this.mouthOpenThreshold = 0.15,
    this.sustainedGestureDuration = const Duration(milliseconds: 400),
    this.frameSkipCount = 2,
    this.includeLandmarks = false,
    this.captureRequireFrontal = true,
    this.captureMaxYaw = 15.0,
    this.captureMaxPitch = 15.0,
    this.captureRequireOptimalDistance = true,
    this.captureMinBrightness = 0.25,
    this.captureMaxBrightness = 0.80,
    this.captureMinSharpness = 60.0,
    this.captureRequireEyesOpen = true,
    this.captureRequireMouthClosed = false,
    this.captureSustainedDuration = const Duration(milliseconds: 600),
  });
}
