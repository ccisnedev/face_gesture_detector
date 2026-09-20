import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:face_gesture_detector/face_gesture_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelFaceGestureDetector', () {
    late MethodChannelFaceGestureDetector platform;
    late List<MethodCall> capturedCalls;

    const methodChannel = MethodChannel('face_gesture_detector');

    setUp(() {
      platform = MethodChannelFaceGestureDetector();
      capturedCalls = [];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            capturedCalls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
    });

    test(
      'startDetection invokes native method with serialized options',
      () async {
        final options = FaceDetectionOptions.fromConfiguration(
          FaceGestureConfiguration(
            faceDetectionConfidence: 0.7,
            frameSkipCount: 1,
            includeLandmarks: true,
          ),
        );

        await platform.startDetection(options);

        expect(capturedCalls, hasLength(1));
        expect(capturedCalls.first.method, 'startDetection');
        expect(capturedCalls.first.arguments['faceDetectionConfidence'], 0.7);
        expect(capturedCalls.first.arguments['frameSkipCount'], 1);
        expect(capturedCalls.first.arguments['includeLandmarks'], isTrue);
      },
    );

    test('stopDetection invokes native method', () async {
      await platform.stopDetection();

      expect(capturedCalls, hasLength(1));
      expect(capturedCalls.first.method, 'stopDetection');
    });

    test('faceFrameStream returns a Stream from EventChannel', () {
      // Verify the stream is accessible without throwing
      final stream = platform.faceFrameStream;
      expect(stream, isA<Stream<Map<String, dynamic>>>());
    });

    test('processCapturedPhoto forwards args and returns the reply', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            capturedCalls.add(call);
            return <Object?, Object?>{
              'path': '/cache/out.jpg',
              'width': 810,
              'height': 1080,
              'brightness': 0.4,
              'sharpness': 123.0,
              'cropApplied': true,
            };
          });

      final args = const CaptureOptions().toPlatformMap(path: '/tmp/in.jpg');
      final reply = await platform.processCapturedPhoto(args);

      expect(capturedCalls.single.method, 'processCapturedPhoto');
      expect(capturedCalls.single.arguments['path'], '/tmp/in.jpg');
      expect(capturedCalls.single.arguments['targetShortSide'], 1080);
      expect(reply['path'], '/cache/out.jpg');
      expect(reply['width'], 810);
      expect(reply['cropApplied'], isTrue);
    });

    test('processCapturedPhoto throws when native returns nothing', () async {
      expect(
        () => platform.processCapturedPhoto({'path': 'x'}),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
