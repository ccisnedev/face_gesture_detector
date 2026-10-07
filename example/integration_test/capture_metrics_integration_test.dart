// Prints live pipeline metrics per camera preset on a physical device:
// pipeline warm-up time, frame rate, analysis frame size, brightness /
// sharpness range and the resolution/latency of capturePhoto().
// Diagnostic — no strict assertions beyond "the pipeline runs and a photo
// is produced".
//
// The screen must stay on (adb shell svc power stayon true) — CameraX does
// not answer takePicture() once the preview surface is gone.
//
// Run: flutter test integration_test/capture_metrics_integration_test.dart -d <device_id>

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:face_gesture_detector/face_gesture_detector.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final preset in [ResolutionPreset.high, ResolutionPreset.veryHigh]) {
    testWidgets('metrics with ${preset.name}', (WidgetTester tester) async {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final camera = CameraController(
        front,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await camera.initialize();

      final controller = FaceGestureDetectorController();
      final frames = <FaceFrame>[];
      final mounted = DateTime.now();

      await tester.pumpWidget(
        MaterialApp(
          home: FaceGestureDetector(
            configuration: FaceGestureConfiguration(frameSkipCount: 0),
            cameraController: camera,
            controller: controller,
            onFaceFrame: frames.add,
            child: CameraPreview(camera),
          ),
        ),
      );

      // Warm-up: MediaPipe model load + delegate init happen inside
      // startDetection(), before the image stream starts.
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (frames.isEmpty && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      });
      final warmUp = DateTime.now().difference(mounted);
      debugPrint(
        '[metrics] preset=${preset.name} first frame after ${warmUp.inMilliseconds}ms',
      );
      frames.clear();

      const window = Duration(seconds: 6);
      await tester.runAsync(() => Future<void>.delayed(window));
      await tester.pump();

      final withFace = frames.where((f) => f.isFaceDetected).length;
      final b = frames.map((f) => f.quality.brightness).toList()..sort();
      final s = frames.map((f) => f.quality.sharpness).toList()..sort();
      String range(List<double> v, int digits) => v.isEmpty
          ? '-'
          : '${v.first.toStringAsFixed(digits)}..${v.last.toStringAsFixed(digits)} '
                '(median ${v[v.length ~/ 2].toStringAsFixed(digits)})';
      debugPrint(
        '[metrics] preset=${preset.name} frames=${frames.length} in ${window.inSeconds}s '
        '(${(frames.length / window.inSeconds).toStringAsFixed(1)} fps) '
        'frame=${frames.isEmpty ? '?' : '${frames.last.frameWidth}x${frames.last.frameHeight}'} '
        'face=$withFace brightness=${range(b, 3)} sharpness=${range(s, 1)}',
      );

      await tester.runAsync(() async {
        final started = DateTime.now();
        try {
          final photo = await controller.capturePhoto(
            options: const CaptureOptions(targetShortSide: 1080),
          );
          debugPrint(
            '[metrics] preset=${preset.name} capture=${photo.width}x${photo.height} '
            'in ${DateTime.now().difference(started).inMilliseconds}ms '
            'crop=${photo.cropApplied} b=${photo.quality.brightness.toStringAsFixed(3)} '
            's=${photo.quality.sharpness.toStringAsFixed(1)} '
            'bytes=${File(photo.path).lengthSync()}',
          );
          expect(File(photo.path).existsSync(), isTrue);
        } catch (e) {
          debugPrint('[metrics] preset=${preset.name} capture FAILED: $e');
          rethrow;
        }
      });

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await camera.dispose();
      });
    });
  }
}
