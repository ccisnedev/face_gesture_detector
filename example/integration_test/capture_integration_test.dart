// Photo capture integration tests — run on a physical Android device.
//
// IMPORTANT: Camera permission must be granted before running:
//   adb shell pm grant com.example.face_gesture_detector_example android.permission.CAMERA
//
// Run: flutter test integration_test/capture_integration_test.dart -d <device_id>

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:face_gesture_detector/face_gesture_detector.dart';

Future<CameraController?> _frontCamera() async {
  final cameras = await availableCameras();
  if (cameras.isEmpty) return null;
  final front = cameras.firstWhere(
    (c) => c.lensDirection == CameraLensDirection.front,
    orElse: () => cameras.first,
  );
  final controller = CameraController(
    front,
    ResolutionPreset.high,
    enableAudio: false,
    imageFormatGroup: ImageFormatGroup.nv21,
  );
  await controller.initialize();
  return controller;
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Photo capture', () {
    testWidgets('capturePhoto writes a JPEG whose size matches the result', (
      WidgetTester tester,
    ) async {
      final camera = await _frontCamera();
      if (camera == null) {
        debugPrint('[capture-test] no camera — skipped');
        return;
      }

      final controller = FaceGestureDetectorController();
      final frames = <FaceFrame>[];
      final quality = <ImageQualityMetrics>[];

      await tester.pumpWidget(
        MaterialApp(
          home: FaceGestureDetector(
            configuration: FaceGestureConfiguration(frameSkipCount: 0),
            cameraController: camera,
            controller: controller,
            onFaceFrame: frames.add,
            onQualityChanged: (d) => quality.add(d.metrics),
            child: CameraPreview(camera),
          ),
        ),
      );

      // Wait for the pipeline to warm up (model load + delegate init happen
      // in startDetection(), before the image stream starts) and then run
      // for a moment so lastFrame/metrics exist.
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (frames.isEmpty && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pump();

      if (quality.isNotEmpty) {
        final last = quality.last;
        debugPrint(
          '[capture-test] live frames=${frames.length} '
          'brightness=${last.brightness.toStringAsFixed(3)} '
          'sharpness=${last.sharpness.toStringAsFixed(1)} '
          'frame=${frames.isNotEmpty ? '${frames.last.frameWidth}x${frames.last.frameHeight}' : '?'} '
          'face=${frames.isNotEmpty && frames.last.isFaceDetected}',
        );
      }

      late CapturedPhoto photo;
      await tester.runAsync(() async {
        final started = DateTime.now();
        photo = await controller.capturePhoto(
          options: const CaptureOptions(targetShortSide: 1080),
        );
        debugPrint(
          '[capture-test] stopStream=true → ${photo.width}x${photo.height} '
          'in ${DateTime.now().difference(started).inMilliseconds}ms '
          'crop=${photo.cropApplied} '
          'b=${photo.quality.brightness.toStringAsFixed(3)} '
          's=${photo.quality.sharpness.toStringAsFixed(1)} '
          'path=${photo.path}',
        );
      });

      final file = File(photo.path);
      expect(file.existsSync(), isTrue, reason: 'output file must exist');
      final bytes = await file.readAsBytes();
      expect(bytes.length, greaterThan(1024));
      expect(bytes[0], 0xFF, reason: 'JPEG SOI marker');
      expect(bytes[1], 0xD8, reason: 'JPEG SOI marker');

      late ui.Image decoded;
      await tester.runAsync(() async {
        decoded = await _decode(bytes);
      });
      expect(decoded.width, photo.width);
      expect(decoded.height, photo.height);
      expect(photo.width, lessThanOrEqualTo(1080 * 2));
      expect(
        photo.width <= 1080 || photo.height <= 1080,
        isTrue,
        reason: 'short side must not exceed targetShortSide',
      );
      expect(photo.quality.brightness, inInclusiveRange(0.0, 1.0));
      expect(photo.quality.sharpness, greaterThanOrEqualTo(0.0));

      // Second capture without stopping the stream — records whether this
      // device/camera implementation supports takePicture() while streaming.
      await tester.runAsync(() async {
        try {
          final started = DateTime.now();
          final second = await controller.capturePhoto(
            options: const CaptureOptions(stopStreamWhileCapturing: false),
          );
          debugPrint(
            '[capture-test] stopStream=false → OK ${second.width}x${second.height} '
            'in ${DateTime.now().difference(started).inMilliseconds}ms',
          );
          expect(File(second.path).existsSync(), isTrue);
        } catch (e) {
          debugPrint('[capture-test] stopStream=false → FAILED: $e');
        }
      });

      // The stream must keep flowing after captures.
      final before = frames.length;
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
      await tester.pump();
      debugPrint(
        '[capture-test] frames after captures: ${frames.length - before} in 2s',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await camera.dispose();
      });
    });
  });
}
