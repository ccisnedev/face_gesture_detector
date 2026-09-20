import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:face_gesture_detector/face_gesture_detector.dart';

/// A frame that satisfies every default capture gate unless overridden.
FaceFrame _frame({
  Duration timestamp = Duration.zero,
  bool isFaceDetected = true,
  double yaw = 0.0,
  double pitch = 0.0,
  Rect? box,
  int frameWidth = 640,
  int frameHeight = 480,
  double brightness = 0.5,
  double sharpness = 200.0,
  double blinkLeft = 0.05,
  double blinkRight = 0.05,
  double jawOpen = 0.02,
}) {
  return FaceFrame(
    timestamp: timestamp,
    isFaceDetected: isFaceDetected,
    faceConfidence: isFaceDetected ? 1.0 : 0.0,
    // 200×240 in 640×480 → ratio 0.156, inside 0.05..0.40
    faceBoundingBox: box ?? Rect.fromLTWH(220, 120, 200, 240),
    poseAngles: PoseAngles(pitch: pitch, yaw: yaw, roll: 0),
    blendshapes: {
      FaceBlendshape.eyeBlinkLeft: blinkLeft,
      FaceBlendshape.eyeBlinkRight: blinkRight,
      FaceBlendshape.jawOpen: jawOpen,
    },
    landmarks: null,
    quality: ImageQualityMetrics(brightness: brightness, sharpness: sharpness),
    frameWidth: frameWidth,
    frameHeight: frameHeight,
  );
}

void main() {
  group('CaptureReadyRecognizer.evaluate', () {
    late CaptureReadyRecognizer recognizer;

    setUp(() {
      recognizer = CaptureReadyRecognizer(
        configuration: FaceGestureConfiguration(),
        onCaptureReady: (_) {},
        onCaptureBlocked: (_) {},
      );
    });

    test('returns no reasons for a good frame', () {
      expect(recognizer.evaluate(_frame()), isEmpty);
    });

    test('reports noFace (plus brightness) when no face is detected', () {
      expect(recognizer.evaluate(_frame(isFaceDetected: false)), [
        CaptureBlockReason.noFace,
      ]);
      expect(
        recognizer.evaluate(_frame(isFaceDetected: false, brightness: 0.1)),
        [CaptureBlockReason.noFace, CaptureBlockReason.tooDark],
      );
    });

    test('reports notFrontal beyond yaw or pitch tolerance', () {
      expect(recognizer.evaluate(_frame(yaw: 20)), [
        CaptureBlockReason.notFrontal,
      ]);
      expect(recognizer.evaluate(_frame(pitch: -16)), [
        CaptureBlockReason.notFrontal,
      ]);
      expect(recognizer.evaluate(_frame(yaw: 14.9, pitch: 14.9)), isEmpty);
    });

    test('reports tooFar / tooClose from the face box ratio', () {
      // 40×40 in 640×480 → 0.005
      expect(recognizer.evaluate(_frame(box: Rect.fromLTWH(0, 0, 40, 40))), [
        CaptureBlockReason.tooFar,
      ]);
      // 500×400 in 640×480 → 0.65
      expect(recognizer.evaluate(_frame(box: Rect.fromLTWH(0, 0, 500, 400))), [
        CaptureBlockReason.tooClose,
      ]);
    });

    test('skips the distance gate when the frame size is unknown', () {
      final frame = _frame(
        box: Rect.fromLTWH(0, 0, 40, 40),
        frameWidth: 0,
        frameHeight: 0,
      );
      expect(recognizer.evaluate(frame), isEmpty);
    });

    test('reports tooDark / tooBright', () {
      expect(recognizer.evaluate(_frame(brightness: 0.2)), [
        CaptureBlockReason.tooDark,
      ]);
      expect(recognizer.evaluate(_frame(brightness: 0.9)), [
        CaptureBlockReason.tooBright,
      ]);
    });

    test('reports blurry below captureMinSharpness', () {
      expect(recognizer.evaluate(_frame(sharpness: 10)), [
        CaptureBlockReason.blurry,
      ]);
    });

    test('reports eyesClosed when either eye is above blinkThreshold', () {
      expect(recognizer.evaluate(_frame(blinkLeft: 0.6)), [
        CaptureBlockReason.eyesClosed,
      ]);
      expect(recognizer.evaluate(_frame(blinkRight: 0.6)), [
        CaptureBlockReason.eyesClosed,
      ]);
    });

    test('mouthOpen is only checked when captureRequireMouthClosed', () {
      expect(recognizer.evaluate(_frame(jawOpen: 0.5)), isEmpty);

      final strict = CaptureReadyRecognizer(
        configuration: FaceGestureConfiguration(
          captureRequireMouthClosed: true,
        ),
        onCaptureReady: (_) {},
        onCaptureBlocked: (_) {},
      );
      expect(strict.evaluate(_frame(jawOpen: 0.5)), [
        CaptureBlockReason.mouthOpen,
      ]);
    });

    test('lists several reasons in declaration order', () {
      final frame = _frame(yaw: 30, brightness: 0.1, sharpness: 0, blinkLeft: 1);
      expect(recognizer.evaluate(frame), [
        CaptureBlockReason.notFrontal,
        CaptureBlockReason.tooDark,
        CaptureBlockReason.blurry,
        CaptureBlockReason.eyesClosed,
      ]);
    });

    test('gates can be disabled individually', () {
      final relaxed = CaptureReadyRecognizer(
        configuration: FaceGestureConfiguration(
          captureRequireFrontal: false,
          captureRequireOptimalDistance: false,
          captureRequireEyesOpen: false,
          captureMinSharpness: 0,
        ),
        onCaptureReady: (_) {},
        onCaptureBlocked: (_) {},
      );
      final frame = _frame(
        yaw: 40,
        box: Rect.fromLTWH(0, 0, 40, 40),
        sharpness: 0,
        blinkLeft: 1,
      );
      expect(relaxed.evaluate(frame), isEmpty);
    });
  });

  group('CaptureReadyRecognizer events', () {
    late List<CaptureReadyDetails> ready;
    late List<CaptureBlockedDetails> blocked;
    late CaptureReadyRecognizer recognizer;

    setUp(() {
      ready = [];
      blocked = [];
      recognizer = CaptureReadyRecognizer(
        configuration: FaceGestureConfiguration(
          captureSustainedDuration: Duration(milliseconds: 600),
        ),
        onCaptureReady: ready.add,
        onCaptureBlocked: blocked.add,
      );
    });

    test('fires onCaptureReady once after the sustained duration', () {
      recognizer.addFaceFrame(_frame(timestamp: Duration.zero));
      recognizer.addFaceFrame(_frame(timestamp: Duration(milliseconds: 300)));
      expect(ready, isEmpty);

      recognizer.addFaceFrame(_frame(timestamp: Duration(milliseconds: 600)));
      expect(ready, hasLength(1));
      expect(ready.first.sustainedFor, Duration(milliseconds: 600));

      // Still clear — no second event in the same episode.
      recognizer.addFaceFrame(_frame(timestamp: Duration(milliseconds: 900)));
      recognizer.addFaceFrame(_frame(timestamp: Duration(milliseconds: 1500)));
      expect(ready, hasLength(1));
    });

    test('emits onCaptureBlocked on the first frame and on changes only', () {
      recognizer.addFaceFrame(_frame(timestamp: Duration.zero, yaw: 30));
      recognizer.addFaceFrame(
        _frame(timestamp: Duration(milliseconds: 100), yaw: 32),
      );
      expect(blocked, hasLength(1));
      expect(blocked.first.reasons, [CaptureBlockReason.notFrontal]);

      // Reasons change → new event.
      recognizer.addFaceFrame(
        _frame(timestamp: Duration(milliseconds: 200), yaw: 30, brightness: 0.1),
      );
      expect(blocked, hasLength(2));
      expect(blocked.last.reasons, [
        CaptureBlockReason.notFrontal,
        CaptureBlockReason.tooDark,
      ]);

      // Gates clear → event with an empty list ("hold still").
      recognizer.addFaceFrame(_frame(timestamp: Duration(milliseconds: 300)));
      expect(blocked, hasLength(3));
      expect(blocked.last.reasons, isEmpty);
      expect(blocked.last.isClear, isTrue);
    });

    test('a blocked frame restarts the sustained timer and the episode', () {
      recognizer.addFaceFrame(_frame(timestamp: Duration.zero));
      recognizer.addFaceFrame(_frame(timestamp: Duration(milliseconds: 400)));
      recognizer.addFaceFrame(
        _frame(timestamp: Duration(milliseconds: 500), blinkLeft: 1),
      );
      recognizer.addFaceFrame(_frame(timestamp: Duration(milliseconds: 600)));
      recognizer.addFaceFrame(_frame(timestamp: Duration(milliseconds: 1100)));
      expect(ready, isEmpty);

      recognizer.addFaceFrame(_frame(timestamp: Duration(milliseconds: 1200)));
      expect(ready, hasLength(1));

      // Block again, then clear again → a second ready event.
      recognizer.addFaceFrame(
        _frame(timestamp: Duration(milliseconds: 1300), isFaceDetected: false),
      );
      recognizer.addFaceFrame(_frame(timestamp: Duration(milliseconds: 1400)));
      recognizer.addFaceFrame(_frame(timestamp: Duration(milliseconds: 2000)));
      expect(ready, hasLength(2));
    });

    test('reset clears the timer and the last reasons', () {
      recognizer.addFaceFrame(_frame(timestamp: Duration.zero));
      recognizer.addFaceFrame(_frame(timestamp: Duration(milliseconds: 500)));
      recognizer.reset();

      recognizer.addFaceFrame(_frame(timestamp: Duration(milliseconds: 600)));
      expect(ready, isEmpty);
      // After reset the (unchanged) empty reason set is reported again.
      expect(blocked, hasLength(2));

      recognizer.addFaceFrame(_frame(timestamp: Duration(milliseconds: 1200)));
      expect(ready, hasLength(1));
    });
  });
}
