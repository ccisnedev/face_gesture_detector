import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import '../configuration/face_gesture_configuration.dart';
import '../controller/face_gesture_detector_controller.dart';
import '../model/details/blink_details.dart';
import '../model/details/brow_details.dart';
import '../model/details/capture_ready_details.dart';
import '../model/details/distance_details.dart';
import '../model/details/face_detected_details.dart';
import '../model/details/head_nod_details.dart';
import '../model/details/head_turn_details.dart';
import '../model/details/mouth_details.dart';
import '../model/details/pose_details.dart';
import '../model/details/quality_details.dart';
import '../model/details/smile_details.dart';
import '../model/face_frame.dart';
import '../recognizer/blink_recognizer.dart';
import '../recognizer/brow_recognizer.dart';
import '../recognizer/capture_ready_recognizer.dart';
import '../recognizer/face_gesture_recognizer_factory.dart';
import '../recognizer/face_presence_recognizer.dart';
import '../recognizer/head_nod_recognizer.dart';
import '../recognizer/head_turn_recognizer.dart';
import '../recognizer/mouth_recognizer.dart';
import '../recognizer/pose_recognizer.dart';
import '../recognizer/quality_gate_recognizer.dart';
import '../recognizer/raw_frame_recognizer.dart';
import '../recognizer/smile_recognizer.dart';
import 'raw_face_gesture_detector.dart';

/// Layer 1 facade widget that translates declarative callbacks into a
/// recognizer map and delegates to [RawFaceGestureDetector].
///
/// Analogous to [GestureDetector] in Flutter's gesture system. A null
/// callback means its corresponding recognizer is not instantiated
/// (callbacks-as-subscription pattern, zero cost).
///
/// ```dart
/// FaceGestureDetector(
///   configuration: FaceGestureConfiguration(),
///   onFaceDetected: (details) => print('Face found!'),
///   onFaceLost: () => print('Face lost!'),
///   child: CameraPreview(controller: _cameraController),
/// )
/// ```
class FaceGestureDetector extends StatelessWidget {
  // ── Required ────────────────────────────────────────
  final FaceGestureConfiguration configuration;

  // ── Camera ──────────────────────────────────────────
  final CameraController? cameraController;

  // ── Family: Presence ────────────────────────────────
  final ValueChanged<FaceDetectedDetails>? onFaceDetected;
  final VoidCallback? onFaceLost;

  // ── Family: Quality ─────────────────────────────────
  final ValueChanged<QualityDetails>? onQualityChanged;
  final ValueChanged<DistanceDetails>? onDistanceChanged;

  // ── Family: Pose ────────────────────────────────────
  final ValueChanged<PoseDetails>? onPoseChanged;

  // ── Family: Eyes ────────────────────────────────────
  final ValueChanged<BlinkDetails>? onBlinkDetected;

  // ── Family: Mouth ───────────────────────────────────
  final ValueChanged<SmileDetails>? onSmileDetected;
  final ValueChanged<MouthDetails>? onMouthOpened;

  // ── Family: Brows ───────────────────────────────────
  final ValueChanged<BrowDetails>? onBrowRaised;

  // ── Family: Head Turn ───────────────────────────────
  final ValueChanged<HeadTurnDetails>? onHeadTurnDetected;

  // ── Family: Head Nod ────────────────────────────────
  final ValueChanged<HeadNodDetails>? onHeadNodDetected;

  // ── Family: Capture ─────────────────────────────────

  /// Fires once when every capture gate (face, frontal pose, distance,
  /// brightness, sharpness, eyes open, …) has held for
  /// `captureSustainedDuration`. Typically followed by
  /// `controller.capturePhoto()`.
  final ValueChanged<CaptureReadyDetails>? onCaptureReady;

  /// Fires when the set of failing capture gates changes. An empty list
  /// means all gates pass and the sustained timer is running.
  final ValueChanged<CaptureBlockedDetails>? onCaptureBlocked;

  // ── Raw Data ────────────────────────────────────────
  final ValueChanged<FaceFrame>? onFaceFrame;

  // ── Imperative Control ──────────────────────────────
  final FaceGestureDetectorController? controller;

  // ── Composition ─────────────────────────────────────
  final Widget? child;

  const FaceGestureDetector({
    super.key,
    required this.configuration,
    this.cameraController,
    this.onFaceDetected,
    this.onFaceLost,
    this.onQualityChanged,
    this.onDistanceChanged,
    this.onPoseChanged,
    this.onBlinkDetected,
    this.onSmileDetected,
    this.onMouthOpened,
    this.onBrowRaised,
    this.onHeadTurnDetected,
    this.onHeadNodDetected,
    this.onCaptureReady,
    this.onCaptureBlocked,
    this.onFaceFrame,
    this.controller,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final recognizers = <Type, FaceGestureRecognizerFactory>{};

    if (onFaceDetected != null || onFaceLost != null) {
      recognizers[FacePresenceRecognizer] = _FacePresenceFactory(
        configuration: configuration,
        onFaceDetected: onFaceDetected,
        onFaceLost: onFaceLost,
      );
    }

    if (onQualityChanged != null || onDistanceChanged != null) {
      recognizers[QualityGateRecognizer] = _QualityGateFactory(
        configuration: configuration,
        onQualityChanged: onQualityChanged,
        onDistanceChanged: onDistanceChanged,
      );
    }

    if (onPoseChanged != null) {
      recognizers[PoseRecognizer] = _PoseFactory(
        configuration: configuration,
        onPoseChanged: onPoseChanged!,
      );
    }

    if (onBlinkDetected != null) {
      recognizers[BlinkRecognizer] = _BlinkFactory(
        configuration: configuration,
        onBlinkDetected: onBlinkDetected!,
      );
    }

    if (onSmileDetected != null) {
      recognizers[SmileRecognizer] = _SmileFactory(
        configuration: configuration,
        onSmileDetected: onSmileDetected!,
      );
    }

    if (onMouthOpened != null) {
      recognizers[MouthRecognizer] = _MouthFactory(
        configuration: configuration,
        onMouthOpened: onMouthOpened!,
      );
    }

    if (onBrowRaised != null) {
      recognizers[BrowRecognizer] = _BrowFactory(
        configuration: configuration,
        onBrowRaised: onBrowRaised!,
      );
    }

    if (onHeadTurnDetected != null) {
      recognizers[HeadTurnRecognizer] = _HeadTurnFactory(
        configuration: configuration,
        onHeadTurnDetected: onHeadTurnDetected!,
      );
    }

    if (onHeadNodDetected != null) {
      recognizers[HeadNodRecognizer] = _HeadNodFactory(
        configuration: configuration,
        onHeadNodDetected: onHeadNodDetected!,
      );
    }

    if (onCaptureReady != null || onCaptureBlocked != null) {
      recognizers[CaptureReadyRecognizer] = _CaptureReadyFactory(
        configuration: configuration,
        onCaptureReady: onCaptureReady,
        onCaptureBlocked: onCaptureBlocked,
      );
    }

    if (onFaceFrame != null) {
      recognizers[RawFrameRecognizer] = _RawFrameFactory(
        configuration: configuration,
        onFaceFrame: onFaceFrame!,
      );
    }

    return RawFaceGestureDetector(
      configuration: configuration,
      recognizers: recognizers,
      controller: controller,
      cameraController: cameraController,
      child: child,
    );
  }
}

// ── Private Factory Implementations ──────────────────────

class _FacePresenceFactory
    extends FaceGestureRecognizerFactory<FacePresenceRecognizer> {
  final FaceGestureConfiguration configuration;
  final ValueChanged<FaceDetectedDetails>? onFaceDetected;
  final VoidCallback? onFaceLost;

  _FacePresenceFactory({
    required this.configuration,
    this.onFaceDetected,
    this.onFaceLost,
  });

  @override
  FacePresenceRecognizer create() => FacePresenceRecognizer(
    configuration: configuration,
    onFaceDetected: onFaceDetected ?? (_) {},
    onFaceLost: onFaceLost ?? () {},
  );
}

class _QualityGateFactory
    extends FaceGestureRecognizerFactory<QualityGateRecognizer> {
  final FaceGestureConfiguration configuration;
  final ValueChanged<QualityDetails>? onQualityChanged;
  final ValueChanged<DistanceDetails>? onDistanceChanged;

  _QualityGateFactory({
    required this.configuration,
    this.onQualityChanged,
    this.onDistanceChanged,
  });

  @override
  QualityGateRecognizer create() => QualityGateRecognizer(
    configuration: configuration,
    // Frame dimensions default to HD — will be updated with real
    // values once native integration is wired in M3.
    frameWidth: 1280,
    frameHeight: 720,
    onQualityChanged: onQualityChanged ?? (_) {},
    onDistanceChanged: onDistanceChanged ?? (_) {},
  );
}

class _PoseFactory extends FaceGestureRecognizerFactory<PoseRecognizer> {
  final FaceGestureConfiguration configuration;
  final ValueChanged<PoseDetails> onPoseChanged;

  _PoseFactory({required this.configuration, required this.onPoseChanged});

  @override
  PoseRecognizer create() => PoseRecognizer(
    configuration: configuration,
    onPoseChanged: onPoseChanged,
  );
}

class _BlinkFactory extends FaceGestureRecognizerFactory<BlinkRecognizer> {
  final FaceGestureConfiguration configuration;
  final ValueChanged<BlinkDetails> onBlinkDetected;

  _BlinkFactory({required this.configuration, required this.onBlinkDetected});

  @override
  BlinkRecognizer create() => BlinkRecognizer(
    configuration: configuration,
    onBlinkDetected: onBlinkDetected,
  );
}

class _SmileFactory extends FaceGestureRecognizerFactory<SmileRecognizer> {
  final FaceGestureConfiguration configuration;
  final ValueChanged<SmileDetails> onSmileDetected;

  _SmileFactory({required this.configuration, required this.onSmileDetected});

  @override
  SmileRecognizer create() => SmileRecognizer(
    configuration: configuration,
    onSmileDetected: onSmileDetected,
  );
}

class _MouthFactory extends FaceGestureRecognizerFactory<MouthRecognizer> {
  final FaceGestureConfiguration configuration;
  final ValueChanged<MouthDetails> onMouthOpened;

  _MouthFactory({required this.configuration, required this.onMouthOpened});

  @override
  MouthRecognizer create() => MouthRecognizer(
    configuration: configuration,
    onMouthOpened: onMouthOpened,
  );
}

class _BrowFactory extends FaceGestureRecognizerFactory<BrowRecognizer> {
  final FaceGestureConfiguration configuration;
  final ValueChanged<BrowDetails> onBrowRaised;

  _BrowFactory({required this.configuration, required this.onBrowRaised});

  @override
  BrowRecognizer create() =>
      BrowRecognizer(configuration: configuration, onBrowRaised: onBrowRaised);
}

class _HeadTurnFactory
    extends FaceGestureRecognizerFactory<HeadTurnRecognizer> {
  final FaceGestureConfiguration configuration;
  final ValueChanged<HeadTurnDetails> onHeadTurnDetected;

  _HeadTurnFactory({
    required this.configuration,
    required this.onHeadTurnDetected,
  });

  @override
  HeadTurnRecognizer create() => HeadTurnRecognizer(
    configuration: configuration,
    onHeadTurnDetected: onHeadTurnDetected,
  );
}

class _HeadNodFactory extends FaceGestureRecognizerFactory<HeadNodRecognizer> {
  final FaceGestureConfiguration configuration;
  final ValueChanged<HeadNodDetails> onHeadNodDetected;

  _HeadNodFactory({
    required this.configuration,
    required this.onHeadNodDetected,
  });

  @override
  HeadNodRecognizer create() => HeadNodRecognizer(
    configuration: configuration,
    onHeadNodDetected: onHeadNodDetected,
  );
}

class _CaptureReadyFactory
    extends FaceGestureRecognizerFactory<CaptureReadyRecognizer> {
  final FaceGestureConfiguration configuration;
  final ValueChanged<CaptureReadyDetails>? onCaptureReady;
  final ValueChanged<CaptureBlockedDetails>? onCaptureBlocked;

  _CaptureReadyFactory({
    required this.configuration,
    this.onCaptureReady,
    this.onCaptureBlocked,
  });

  @override
  CaptureReadyRecognizer create() => CaptureReadyRecognizer(
    configuration: configuration,
    onCaptureReady: onCaptureReady ?? (_) {},
    onCaptureBlocked: onCaptureBlocked ?? (_) {},
  );
}

class _RawFrameFactory
    extends FaceGestureRecognizerFactory<RawFrameRecognizer> {
  final FaceGestureConfiguration configuration;
  final ValueChanged<FaceFrame> onFaceFrame;

  _RawFrameFactory({required this.configuration, required this.onFaceFrame});

  @override
  RawFrameRecognizer create() => RawFrameRecognizer(
    configuration: configuration,
    onFaceFrame: onFaceFrame,
  );
}
