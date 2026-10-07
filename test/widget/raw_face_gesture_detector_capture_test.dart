import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:face_gesture_detector/face_gesture_detector.dart';

/// Records the calls made by the capture flow.
class _FakeCameraAdapter implements CameraCaptureAdapter {
  final List<String> calls = [];
  bool initialized = true;
  int orientation = 270;
  Object? takePictureError;

  /// When set, takePicture() never completes (simulates a dead camera).
  bool hang = false;

  @override
  bool get isInitialized => initialized;

  @override
  int get sensorOrientation => orientation;

  @override
  Future<String> takePicture() async {
    calls.add('takePicture');
    if (takePictureError != null) throw takePictureError!;
    if (hang) return Completer<String>().future;
    return '/tmp/raw.jpg';
  }

  @override
  Future<void> stopImageStream() async => calls.add('stopImageStream');

  @override
  Future<void> startImageStream(void Function(CameraImage image) onImage) async {
    calls.add('startImageStream');
  }
}

class _MockPlatform extends FaceGestureDetectorPlatform {
  Map<String, dynamic>? lastArgs;
  Map<String, dynamic> reply = {
    'path': '/cache/fgd_capture_1.jpg',
    'width': 810,
    'height': 1080,
    'brightness': 0.5,
    'sharpness': 300.0,
    'cropApplied': true,
  };
  final _frames = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Future<void> startDetection(FaceDetectionOptions options) async {}

  @override
  Future<void> stopDetection() async {}

  @override
  Future<void> processFrame(FrameData frameData) async {}

  @override
  Stream<Map<String, dynamic>> get faceFrameStream => _frames.stream;

  @override
  Future<Map<String, dynamic>> processCapturedPhoto(
    Map<String, dynamic> args,
  ) async {
    lastArgs = args;
    return reply;
  }

  void dispose() => _frames.close();
}

class _Recognizer extends FaceGestureRecognizer {
  int frames = 0;
  _Recognizer(super.configuration);
  @override
  void addFaceFrame(FaceFrame frame) => frames++;
  @override
  void reset() {}
  @override
  void dispose() {}
}

class _RecognizerFactory extends FaceGestureRecognizerFactory<_Recognizer> {
  final FaceGestureConfiguration configuration;
  _Recognizer? last;
  _RecognizerFactory(this.configuration);
  @override
  _Recognizer create() => last = _Recognizer(configuration);
}

FaceFrame _faceFrame() => FaceFrame(
  timestamp: Duration(milliseconds: 100),
  isFaceDetected: true,
  faceConfidence: 1,
  // 640×480 raw (landscape) frame; box x 64..192, y 96..288
  faceBoundingBox: Rect.fromLTWH(64, 96, 128, 192),
  poseAngles: PoseAngles(pitch: 2, yaw: -3, roll: 1),
  blendshapes: {},
  landmarks: null,
  quality: ImageQualityMetrics(brightness: 0.5, sharpness: 200),
  frameWidth: 640,
  frameHeight: 480,
);

void main() {
  late _MockPlatform platform;
  late FaceGestureDetectorPlatform original;

  setUp(() {
    original = FaceGestureDetectorPlatform.instance;
    platform = _MockPlatform();
    FaceGestureDetectorPlatform.instance = platform;
  });

  tearDown(() {
    FaceGestureDetectorPlatform.instance = original;
    platform.dispose();
  });

  Future<RawFaceGestureDetectorState> pumpDetector(
    WidgetTester tester, {
    FaceGestureDetectorController? controller,
    Map<Type, FaceGestureRecognizerFactory> recognizers = const {},
  }) async {
    await tester.pumpWidget(
      RawFaceGestureDetector(
        configuration: FaceGestureConfiguration(frameSkipCount: 0),
        recognizers: recognizers,
        controller: controller,
        child: SizedBox.shrink(),
      ),
    );
    return tester.state<RawFaceGestureDetectorState>(
      find.byType(RawFaceGestureDetector),
    );
  }

  group('controller attachment', () {
    testWidgets('attaches on mount and detaches on dispose', (tester) async {
      final controller = FaceGestureDetectorController();
      expect(controller.isAttached, isFalse);

      await pumpDetector(tester, controller: controller);
      expect(controller.isAttached, isTrue);

      await tester.pumpWidget(SizedBox.shrink());
      expect(controller.isAttached, isFalse);
    });

    testWidgets('exposes the last dispatched frame', (tester) async {
      final controller = FaceGestureDetectorController();
      final state = await pumpDetector(tester, controller: controller);

      expect(controller.lastFrame, isNull);
      final frame = _faceFrame();
      state.dispatchFrame(frame);
      expect(controller.lastFrame, same(frame));
    });

    testWidgets('remembers the last frame even while paused', (tester) async {
      final controller = FaceGestureDetectorController();
      final state = await pumpDetector(tester, controller: controller);

      controller.pause();
      final frame = _faceFrame();
      state.dispatchFrame(frame);
      expect(state.lastFrame, same(frame));
    });
  });

  group('capturePhoto', () {
    testWidgets('throws without a camera', (tester) async {
      final controller = FaceGestureDetectorController();
      await pumpDetector(tester, controller: controller);

      await expectLater(controller.capturePhoto(), throwsStateError);
    });

    testWidgets('throws when the camera is not initialized', (tester) async {
      final controller = FaceGestureDetectorController();
      final state = await pumpDetector(tester, controller: controller);
      state.debugCaptureAdapter = _FakeCameraAdapter()..initialized = false;

      await expectLater(controller.capturePhoto(), throwsStateError);
    });

    testWidgets(
      'maps the last face box to upright coordinates and calls native',
      (tester) async {
        final controller = FaceGestureDetectorController();
        final state = await pumpDetector(tester, controller: controller);
        final camera = _FakeCameraAdapter()..orientation = 270;
        state.debugCaptureAdapter = camera;
        state.dispatchFrame(_faceFrame());

        final photo = await controller.capturePhoto(
          options: const CaptureOptions(marginFactor: 0.5, jpegQuality: 90),
        );

        expect(camera.calls, ['takePicture']);
        final args = platform.lastArgs!;
        expect(args['path'], '/tmp/raw.jpg');
        expect(args['marginFactor'], 0.5);
        expect(args['jpegQuality'], 90);
        expect(args['mirror'], isFalse);

        // Raw box normalized: x 0.1..0.3, y 0.2..0.6 in a 640×480 frame.
        // 270° CW → (x, y) → (y, 1 - x): x' 0.2..0.6, y' 0.7..0.9
        final face = Map<String, dynamic>.from(args['faceRect'] as Map);
        expect(face['left'], closeTo(0.2, 1e-9));
        expect(face['top'], closeTo(0.7, 1e-9));
        expect(face['width'], closeTo(0.4, 1e-9));
        expect(face['height'], closeTo(0.2, 1e-9));

        expect(photo.path, '/cache/fgd_capture_1.jpg');
        expect(photo.width, 810);
        expect(photo.height, 1080);
        expect(photo.cropApplied, isTrue);
        expect(photo.quality.sharpness, 300);
        expect(photo.faceRect!.left, closeTo(0.2, 1e-9));
        expect(photo.pose!.yaw, -3);
        expect(controller.isCapturing, isFalse);
      },
    );

    testWidgets('sends no face box when cropToFace is off or no face', (
      tester,
    ) async {
      final controller = FaceGestureDetectorController();
      final state = await pumpDetector(tester, controller: controller);
      state.debugCaptureAdapter = _FakeCameraAdapter();

      await controller.capturePhoto();
      expect(platform.lastArgs!['faceRect'], isNull);

      state.dispatchFrame(_faceFrame());
      await controller.capturePhoto(
        options: const CaptureOptions(cropToFace: false),
      );
      expect(platform.lastArgs!['faceRect'], isNull);
    });

    testWidgets('does not dispatch frames to recognizers while capturing', (
      tester,
    ) async {
      final controller = FaceGestureDetectorController();
      final factory = _RecognizerFactory(FaceGestureConfiguration());
      final state = await pumpDetector(
        tester,
        controller: controller,
        recognizers: {_Recognizer: factory},
      );
      final camera = _FakeCameraAdapter();
      state.debugCaptureAdapter = camera;

      state.dispatchFrame(_faceFrame());
      expect(factory.last!.frames, 1);

      final pending = controller.capturePhoto();
      // A frame arriving mid-capture is remembered but not dispatched.
      state.dispatchFrame(_faceFrame());
      expect(factory.last!.frames, 1);
      await pending;

      state.dispatchFrame(_faceFrame());
      expect(factory.last!.frames, 2);
    });

    testWidgets('rejects concurrent captures', (tester) async {
      final controller = FaceGestureDetectorController();
      final state = await pumpDetector(tester, controller: controller);
      state.debugCaptureAdapter = _FakeCameraAdapter();

      final first = controller.capturePhoto();
      expect(controller.isCapturing, isTrue);
      await expectLater(controller.capturePhoto(), throwsStateError);
      await first;
      expect(controller.isCapturing, isFalse);
    });

    testWidgets('times out when takePicture never answers', (tester) async {
      final controller = FaceGestureDetectorController();
      final state = await pumpDetector(tester, controller: controller);
      state.debugCaptureAdapter = _FakeCameraAdapter()..hang = true;

      await tester.runAsync(() async {
        await expectLater(
          controller.capturePhoto(
            options: const CaptureOptions(timeout: Duration(milliseconds: 50)),
          ),
          throwsA(isA<TimeoutException>()),
        );
      });
      expect(controller.isCapturing, isFalse);
      expect(platform.lastArgs, isNull);

      // Recognizers receive frames again after the failed capture.
      state.dispatchFrame(_faceFrame());
      expect(state.lastFrame, isNotNull);
    });

    testWidgets('propagates takePicture errors and clears the flag', (
      tester,
    ) async {
      final controller = FaceGestureDetectorController();
      final state = await pumpDetector(tester, controller: controller);
      state.debugCaptureAdapter = _FakeCameraAdapter()
        ..takePictureError = CameraException('fail', 'boom');

      await expectLater(
        controller.capturePhoto(),
        throwsA(isA<CameraException>()),
      );
      expect(controller.isCapturing, isFalse);
      expect(platform.lastArgs, isNull);

      // A later capture works again.
      state.debugCaptureAdapter = _FakeCameraAdapter();
      final photo = await controller.capturePhoto();
      expect(photo.path, isNotEmpty);
    });
  });
}
