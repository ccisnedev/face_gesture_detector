import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:face_gesture_detector/face_gesture_detector.dart';

void main() {
  group('FaceGestureDetectorController', () {
    late FaceGestureDetectorController controller;

    setUp(() {
      controller = FaceGestureDetectorController();
    });

    test('starts in non-paused state', () {
      expect(controller.isPaused, isFalse);
    });

    test('pause sets isPaused to true', () {
      controller.pause();
      expect(controller.isPaused, isTrue);
    });

    test('resume sets isPaused to false after pause', () {
      controller.pause();
      controller.resume();
      expect(controller.isPaused, isFalse);
    });

    test('reset notifies listeners', () {
      var resetCount = 0;
      controller.addListener(() => resetCount++);
      controller.reset();
      expect(resetCount, 1);
    });

    test('pause notifies listeners', () {
      var callCount = 0;
      controller.addListener(() => callCount++);
      controller.pause();
      expect(callCount, 1);
    });

    test('resume notifies listeners', () {
      var callCount = 0;
      controller.pause();
      controller.addListener(() => callCount++);
      controller.resume();
      expect(callCount, 1);
    });

    test('dispose prevents further notifications', () {
      var callCount = 0;
      controller.addListener(() => callCount++);
      controller.dispose();

      // After dispose, calling methods should not crash
      // but we don't expect notifications
    });

    group('capture', () {
      test('is not attached and has no frame initially', () {
        expect(controller.isAttached, isFalse);
        expect(controller.isCapturing, isFalse);
        expect(controller.lastFrame, isNull);
      });

      test('capturePhoto throws when not attached', () async {
        await expectLater(controller.capturePhoto(), throwsStateError);
      });

      test('attach/detach track the host and forward capture', () async {
        final host = _FakeHost();
        controller.attach(host);
        expect(controller.isAttached, isTrue);
        expect(controller.lastFrame, same(host.lastFrame));

        final photo = await controller.capturePhoto(
          options: const CaptureOptions(jpegQuality: 77),
        );
        expect(host.lastOptions!.jpegQuality, 77);
        expect(photo.path, 'fake.jpg');

        controller.detach(host);
        expect(controller.isAttached, isFalse);
      });

      test('detach ignores a different host', () {
        final a = _FakeHost();
        final b = _FakeHost();
        controller.attach(a);
        controller.detach(b);
        expect(controller.isAttached, isTrue);
      });

      test('attach and capture do not notify listeners', () async {
        var notifications = 0;
        controller.addListener(() => notifications++);
        controller.attach(_FakeHost());
        await controller.capturePhoto();
        expect(notifications, 0);
      });

      test('isCapturing is true only during the capture', () async {
        final host = _FakeHost();
        controller.attach(host);

        final pending = controller.capturePhoto();
        expect(controller.isCapturing, isTrue);
        await expectLater(controller.capturePhoto(), throwsStateError);
        host.complete();
        await pending;
        expect(controller.isCapturing, isFalse);
      });

      test('isCapturing is cleared when the host fails', () async {
        final host = _FakeHost()..error = StateError('camera gone');
        controller.attach(host);

        await expectLater(controller.capturePhoto(), throwsStateError);
        expect(controller.isCapturing, isFalse);
      });
    });
  });
}

class _FakeHost implements FaceCaptureHost {
  CaptureOptions? lastOptions;
  Object? error;
  Completer<void>? _gate;

  @override
  FaceFrame? lastFrame = FaceFrame(
    timestamp: Duration.zero,
    isFaceDetected: false,
    faceConfidence: 0,
    faceBoundingBox: Rect.zero,
    poseAngles: PoseAngles(pitch: 0, yaw: 0, roll: 0),
    blendshapes: {},
    landmarks: null,
    quality: ImageQualityMetrics(brightness: 0, sharpness: 0),
  );

  /// Releases a capture started while [hold] was set.
  void complete() => _gate?.complete();

  @override
  Future<CapturedPhoto> capturePhoto(CaptureOptions options) async {
    lastOptions = options;
    if (error != null) throw error!;
    _gate = Completer<void>();
    // Yield so the caller can observe isCapturing; complete() unblocks,
    // and a microtask timeout keeps tests that never call it moving.
    await Future.any([_gate!.future, Future<void>.delayed(Duration.zero)]);
    return CapturedPhoto(
      path: 'fake.jpg',
      width: 1,
      height: 1,
      faceRect: null,
      pose: null,
      quality: ImageQualityMetrics(brightness: 0.5, sharpness: 100),
      cropApplied: false,
      capturedAt: DateTime(2026),
    );
  }
}
