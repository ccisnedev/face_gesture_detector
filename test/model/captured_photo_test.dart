import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:face_gesture_detector/face_gesture_detector.dart';

void main() {
  group('CaptureOptions', () {
    test('has biometric-friendly defaults', () {
      const options = CaptureOptions();
      expect(options.mirror, isFalse);
      expect(options.cropToFace, isTrue);
      expect(options.marginFactor, 0.6);
      expect(options.aspectRatio, 0.75);
      expect(options.targetShortSide, 1080);
      expect(options.jpegQuality, 92);
      expect(options.outputDir, isNull);
      expect(options.stopStreamWhileCapturing, isTrue);
    });

    test('toPlatformMap serializes every native field', () {
      const options = CaptureOptions(
        mirror: true,
        marginFactor: 0.5,
        aspectRatio: null,
        targetShortSide: 720,
        jpegQuality: 80,
        outputDir: '/tmp/out',
      );
      // Binary-exact fractions so Rect's right-left arithmetic is exact.
      final map = options.toPlatformMap(
        path: '/tmp/in.jpg',
        faceRect: Rect.fromLTWH(0.125, 0.25, 0.375, 0.5),
      );

      expect(map, {
        'path': '/tmp/in.jpg',
        'mirror': true,
        'faceRect': {'left': 0.125, 'top': 0.25, 'width': 0.375, 'height': 0.5},
        'marginFactor': 0.5,
        'aspectRatio': null,
        'targetShortSide': 720,
        'jpegQuality': 80,
        'outputDir': '/tmp/out',
      });
    });

    test('toPlatformMap sends a null faceRect when none is given', () {
      final map = const CaptureOptions().toPlatformMap(path: 'p.jpg');
      expect(map['faceRect'], isNull);
    });
  });

  group('CapturedPhoto.fromPlatformMap', () {
    test('reads the native reply and attaches Dart-side metadata', () {
      final at = DateTime(2026, 9, 3, 10, 0);
      final photo = CapturedPhoto.fromPlatformMap(
        {
          'path': '/cache/fgd_capture_1.jpg',
          'width': 810,
          'height': 1080,
          'brightness': 0.52,
          'sharpness': 250.5,
          'cropApplied': true,
        },
        faceRect: Rect.fromLTWH(0.2, 0.3, 0.4, 0.4),
        pose: PoseAngles(pitch: 1, yaw: -2, roll: 0.5),
        capturedAt: at,
      );

      expect(photo.path, '/cache/fgd_capture_1.jpg');
      expect(photo.width, 810);
      expect(photo.height, 1080);
      expect(photo.quality.brightness, 0.52);
      expect(photo.quality.sharpness, 250.5);
      expect(photo.cropApplied, isTrue);
      expect(photo.faceRect, Rect.fromLTWH(0.2, 0.3, 0.4, 0.4));
      expect(photo.pose!.yaw, -2);
      expect(photo.capturedAt, at);
    });

    test('tolerates missing optional fields', () {
      final photo = CapturedPhoto.fromPlatformMap({
        'path': 'p.jpg',
        'width': 10,
        'height': 20,
      });
      expect(photo.quality.brightness, 0);
      expect(photo.quality.sharpness, 0);
      expect(photo.cropApplied, isFalse);
      expect(photo.faceRect, isNull);
      expect(photo.pose, isNull);
    });
  });
}
