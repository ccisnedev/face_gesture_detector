import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:face_gesture_detector/face_gesture_detector.dart';

void main() {
  group('FaceGestureDetector', () {
    testWidgets(
      'creates only FacePresenceRecognizer when only presence callbacks given',
      (tester) async {
        await tester.pumpWidget(
          FaceGestureDetector(
            configuration: FaceGestureConfiguration(),
            onFaceDetected: (_) {},
            child: SizedBox.shrink(),
          ),
        );

        final rawWidget = tester.widget<RawFaceGestureDetector>(
          find.byType(RawFaceGestureDetector),
        );

        expect(rawWidget.recognizers, hasLength(1));
        expect(rawWidget.recognizers, contains(FacePresenceRecognizer));
      },
    );

    testWidgets('creates no recognizers when no callbacks given', (
      tester,
    ) async {
      await tester.pumpWidget(
        FaceGestureDetector(
          configuration: FaceGestureConfiguration(),
          child: SizedBox.shrink(),
        ),
      );

      final rawWidget = tester.widget<RawFaceGestureDetector>(
        find.byType(RawFaceGestureDetector),
      );

      expect(rawWidget.recognizers, isEmpty);
    });

    testWidgets('creates all recognizers when all callbacks given', (
      tester,
    ) async {
      await tester.pumpWidget(
        FaceGestureDetector(
          configuration: FaceGestureConfiguration(),
          onFaceDetected: (_) {},
          onFaceLost: () {},
          onQualityChanged: (_) {},
          onDistanceChanged: (_) {},
          onPoseChanged: (_) {},
          onBlinkDetected: (_) {},
          onSmileDetected: (_) {},
          onMouthOpened: (_) {},
          onBrowRaised: (_) {},
          onHeadTurnDetected: (_) {},
          onHeadNodDetected: (_) {},
          onCaptureReady: (_) {},
          onCaptureBlocked: (_) {},
          onFaceFrame: (_) {},
          child: SizedBox.shrink(),
        ),
      );

      final rawWidget = tester.widget<RawFaceGestureDetector>(
        find.byType(RawFaceGestureDetector),
      );

      // Presence, Quality, Pose, Blink, Smile, Mouth, Brow, HeadTurn,
      // HeadNod, CaptureReady, RawFrame
      expect(rawWidget.recognizers, hasLength(11));
      expect(rawWidget.recognizers, contains(CaptureReadyRecognizer));
    });

    testWidgets('creates CaptureReadyRecognizer for either capture callback', (
      tester,
    ) async {
      await tester.pumpWidget(
        FaceGestureDetector(
          configuration: FaceGestureConfiguration(),
          onCaptureBlocked: (_) {},
          child: SizedBox.shrink(),
        ),
      );

      final rawWidget = tester.widget<RawFaceGestureDetector>(
        find.byType(RawFaceGestureDetector),
      );

      expect(rawWidget.recognizers.keys, [CaptureReadyRecognizer]);
    });

    testWidgets('forwards controller to RawFaceGestureDetector', (
      tester,
    ) async {
      final controller = FaceGestureDetectorController();

      await tester.pumpWidget(
        FaceGestureDetector(
          configuration: FaceGestureConfiguration(),
          controller: controller,
          onFaceDetected: (_) {},
          child: SizedBox.shrink(),
        ),
      );

      final rawWidget = tester.widget<RawFaceGestureDetector>(
        find.byType(RawFaceGestureDetector),
      );

      expect(rawWidget.controller, same(controller));
    });

    testWidgets('forwards configuration to RawFaceGestureDetector', (
      tester,
    ) async {
      final config = FaceGestureConfiguration(blinkThreshold: 0.99);

      await tester.pumpWidget(
        FaceGestureDetector(
          configuration: config,
          onBlinkDetected: (_) {},
          child: SizedBox.shrink(),
        ),
      );

      final rawWidget = tester.widget<RawFaceGestureDetector>(
        find.byType(RawFaceGestureDetector),
      );

      expect(rawWidget.configuration, same(config));
    });
  });
}
