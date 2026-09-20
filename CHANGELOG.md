# Changelog
All notable changes to this project will be documented in this file.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/)
and the project adheres to [Semantic Versioning](https://semver.org/).

## 0.3.0

Photo capture, real image-quality metrics and Google Play 16 KB compliance.
(0.2.4 / 0.2.5 were internal, never published.)

### Added
- **Photo capture**: `FaceGestureDetectorController.capturePhoto({CaptureOptions})` takes a picture with the attached `CameraController` and post-processes it natively — EXIF orientation, optional mirror, crop around the last detected face (with margin and aspect ratio), downscale to `targetShortSide` (never upscale), JPEG re-encode and quality metrics of the result. Returns a `CapturedPhoto` (`path`, `width`, `height`, `faceRect`, `pose`, `quality`, `cropApplied`, `capturedAt`). `CaptureOptions.timeout` (10 s) bounds `takePicture()` and the native processing; the image stream is restarted even when the capture fails or times out.
- **`CaptureReadyRecognizer`** with `onCaptureReady` / `onCaptureBlocked` callbacks on `FaceGestureDetector`: evaluates face presence, frontal pose, distance, brightness, sharpness, eyes open and (optionally) mouth closed on every frame; `onCaptureBlocked` reports the changing set of `CaptureBlockReason`s (an empty set means "hold still"), `onCaptureReady` fires once per episode after `captureSustainedDuration`.
- `FaceGestureConfiguration` capture gates: `captureRequireFrontal`, `captureMaxYaw`, `captureMaxPitch`, `captureRequireOptimalDistance`, `captureMinBrightness`, `captureMaxBrightness`, `captureMinSharpness`, `captureRequireEyesOpen`, `captureRequireMouthClosed`, `captureSustainedDuration`.
- `FaceFrame.frameWidth` / `frameHeight` (size of the raw camera frame the bounding box refers to), reported by the native layer.
- `FaceGestureDetectorController.isAttached`, `isCapturing`, `lastFrame`; `FaceCaptureHost` contract implemented by `RawFaceGestureDetectorState`.
- `mapSensorRectToUpright()` — maps a rect from the raw sensor frame to the upright image for a given `sensorOrientation`.
- `CameraCaptureAdapter` / `CameraControllerCaptureAdapter` (camera seam used by capture; injectable in tests via `RawFaceGestureDetectorState.debugCaptureAdapter`).
- Platform interface: `processCapturedPhoto(Map args)`; native `PhotoProcessor` (Kotlin) and `QualityMetrics` (pure Kotlin, JVM-tested).
- Example app: Capture button, Auto-capture switch, live gate status and metrics overlay, thumbnail of the last capture; integration test `capture_integration_test.dart`.

### Changed
- **MediaPipe `tasks-vision` 0.10.21 → 0.10.26.1**. 0.10.21 shipped `libmediapipe_tasks_vision_jni.so` aligned to 4 KB pages, which Google Play rejects for apps targeting Android 15+ (16 KB page-size requirement, enforced since 2025-11-01). 0.10.26.1 is aligned to 16 KB. Consumer apps need AGP ≥ 8.5.1 and `useLegacyPackaging = false` (the default when `minSdk ≥ 23`).
- **Real quality metrics**: `ImageQualityMetrics.brightness` (mean of the NV21 Y plane, subsampled) and `sharpness` (variance of the Laplacian inside the face box, subsampled to ~160 columns) are now measured natively on the exact frame each result belongs to. They were hard-coded to `0.5` / `100.0` before.
- `QualityGateRecognizer` uses `captureMin/MaxBrightness` and `captureMinSharpness` for `isSufficientForCapture`, and the real frame size (when reported) for the distance ratio.
- Frames received while a capture is in progress are remembered as `lastFrame` but not dispatched to recognizers.
- Bumped `camera` dependency from `^0.11.1` to `^0.12.0`; added `androidx.exifinterface:exifinterface:1.4.1`.
- Example app camera preset `medium` → `high`.

### Fixed
- Distance classification no longer assumes a 1280×720 frame when the native layer reports the real size.

---

## 0.2.3

### Fixed
- **Release APK crash (R8/ProGuard)**: R8 class-merging optimization broke MediaPipe's JNI native library loading via stack inspection, causing `ExceptionInInitializerError` at runtime. Added `-dontoptimize` and explicit `-keep` rules for MediaPipe, protobuf, and plugin classes in consumer ProGuard rules.
- **Euler angles rotated 90°**: Camera sensor orientation (`sensorOrientation=270` on most front cameras) was sent from Dart but never applied on the native side. MediaPipe computed angles in raw sensor coordinates, causing pitch/yaw/roll to be misassigned (e.g. "head nod up" fired when turning right). Now compensated via `correctAnglesForRotation()` after Euler extraction.
- **Distance "ok" range too narrow**: Default thresholds (`minDistanceRatio=0.20`, `maxDistanceRatio=0.60`) required holding the device uncomfortably close. Relaxed to `0.05`/`0.40` for comfortable arm-length usage.

---

## 0.2.2

### Fixed
- Corrected CHANGELOG to accurately reflect the 0.2.0 and 0.2.1 release history

---

## 0.2.1

### Fixed
- **Deep-cast nested platform channel maps**: `FaceFrame.fromMap` now uses `Map<String, dynamic>.from()` for nested maps (`faceBoundingBox`, `poseAngles`, `quality`, `blendshapes`, `landmarks`) instead of direct `as Map<String, dynamic>` casts that failed at runtime with `_Map<Object?, Object?>`
- **Face confidence always 0.00**: The `_neutral` blendshape score was incorrectly used as face detection confidence; now reports `1.0` when a face is detected (MediaPipe already filters by `minFaceDetectionConfidence`)

---

## 0.2.0

### Added
- **Camera integration**: `FaceGestureDetector` accepts an optional `cameraController` parameter, wiring the full camera → native → recognizer pipeline automatically
- **Real-time detection**: `RawFaceGestureDetector` manages `startDetection`, `processFrame`, `faceFrameStream`, and `stopDetection` lifecycle when a `CameraController` is provided
- **Example app**: Fully functional demo with live front-camera preview, face detection indicator, event log, and all 10 gesture callbacks
- **Integration tests**: Camera pipeline tests on physical device (camera init, processFrame, faceFrameStream)

### Changed
- `cameraController` parameter added to `FaceGestureDetector` and `RawFaceGestureDetector` (optional — `null` preserves test/manual mode)
- `camera: ^0.11.1` added as a dependency
- Example app requires `android.permission.CAMERA`

---

## 0.1.0-dev

### Added
- **Data Model**: `FaceFrame`, `FaceBlendshape` (52 values), `PoseAngles`, `FaceLandmark`, `ImageQualityMetrics`
- **Details objects**: `FaceDetectedDetails`, `QualityDetails`, `DistanceDetails`, `PoseDetails`, `BlinkDetails`, `SmileDetails`, `MouthDetails`, `BrowDetails`, `HeadTurnDetails`, `HeadNodDetails`
- **Configuration**: `FaceGestureConfiguration` with calibrated defaults
- **Platform interface**: `FaceGestureDetectorPlatform` + `MethodChannelFaceGestureDetector` + `processFrame()`
- **Recognizers**: `FacePresenceRecognizer`, `QualityGateRecognizer`, `PoseRecognizer`, `BlinkRecognizer`, `SmileRecognizer`, `MouthRecognizer`, `BrowRecognizer`, `HeadTurnRecognizer`, `HeadNodRecognizer`, `RawFrameRecognizer`
- **Widgets**: `RawFaceGestureDetector` (Layer 2), `FaceGestureDetector` (Layer 1 facade)
- **Controller**: `FaceGestureDetectorController` with pause/resume/reset
- **Native Android**: `FaceLandmarkerEngine` (MediaPipe LIVE_STREAM + GPU delegate), `EulerAngleCalculator` (pitch/yaw/roll from 4×4 matrix), `FrameDecoder` (NV21 → MPImage), `SingleSlotFrameBuffer` (lock-free backpressure), `FaceFrameStreamHandler` (EventChannel main-thread emission), `face_landmarker.task` model bundled
- **Example app**: MVP with all callback families and event log
- **Tests**: 117 Dart unit tests, 14 Android JVM unit tests, 3 integration tests on device