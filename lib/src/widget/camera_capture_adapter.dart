import 'package:camera/camera.dart';

/// The subset of camera operations that photo capture needs.
///
/// [RawFaceGestureDetector] wraps its `CameraController` in a
/// [CameraControllerCaptureAdapter]; tests inject a fake through
/// `RawFaceGestureDetectorState.debugCaptureAdapter`.
abstract class CameraCaptureAdapter {
  /// Whether the camera is ready to take pictures.
  bool get isInitialized;

  /// Clockwise rotation (degrees) that turns the raw frame upright.
  int get sensorOrientation;

  /// Takes a full-resolution picture and returns the path of the JPEG.
  Future<String> takePicture();

  /// Stops the analysis image stream.
  Future<void> stopImageStream();

  /// Restarts the analysis image stream with [onImage].
  Future<void> startImageStream(void Function(CameraImage image) onImage);
}

/// [CameraCaptureAdapter] backed by a real [CameraController].
class CameraControllerCaptureAdapter implements CameraCaptureAdapter {
  final CameraController controller;

  const CameraControllerCaptureAdapter(this.controller);

  @override
  bool get isInitialized => controller.value.isInitialized;

  @override
  int get sensorOrientation => controller.description.sensorOrientation;

  @override
  Future<String> takePicture() async {
    final file = await controller.takePicture();
    return file.path;
  }

  @override
  Future<void> stopImageStream() => controller.stopImageStream();

  @override
  Future<void> startImageStream(void Function(CameraImage image) onImage) =>
      controller.startImageStream(onImage);
}
