A Flutter widget that translates camera frames and MediaPipe facial landmarks into high-level semantic callbacks — exactly as `GestureDetector` translates pointer events into touch gestures.

## Features

- **FaceGestureDetector** — Declarative facade with nullable callbacks per gesture family
- **RawFaceGestureDetector** — Power-user widget for custom recognizer maps
- **11 recognizers** — Presence, Quality, Pose, Blink, Smile, Mouth, Brow, HeadTurn, HeadNod, CaptureReady, RawFrame
- **Temporal logic** — Sustained-duration thresholds, cycle detection, state-transition filtering
- **FaceGestureDetectorController** — Imperative pause / resume / reset / **capturePhoto**
- **Photo capture** — Full-resolution `takePicture()` post-processed natively: EXIF orientation, face crop, downscale, JPEG, quality metrics
- **Real quality metrics** — Brightness (Y plane) and sharpness (Laplacian variance of the face region) measured natively per frame
- **Configurable** — All thresholds, durations and capture gates via `FaceGestureConfiguration`
- **Native Android** — MediaPipe Face Landmarker (0.10.26.1, 16 KB page-size compliant) with GPU delegate, single-slot backpressure, Euler angle extraction

## Quick Start

```dart
import 'package:camera/camera.dart';
import 'package:face_gesture_detector/face_gesture_detector.dart';

// Minimal: presence detection only
FaceGestureDetector(
  configuration: FaceGestureConfiguration(),
  cameraController: cameraController,
  onFaceDetected: (details) => print('Face found: ${details.confidence}'),
  onFaceLost: () => print('Face lost'),
  child: CameraPreview(cameraController),
)

// Full: all gesture families
FaceGestureDetector(
  configuration: FaceGestureConfiguration(
    blinkThreshold: 0.35,
    smileThreshold: 0.5,
    headTurnYawThreshold: 25.0,
    sustainedGestureDuration: Duration(milliseconds: 400),
    frameSkipCount: 2,
  ),
  cameraController: cameraController,
  controller: detectorController,
  onFaceDetected: (d) => handleFace(d),
  onFaceLost: () => handleLost(),
  onBlinkDetected: (d) => handleBlink(d),
  onSmileDetected: (d) => handleSmile(d),
  onHeadTurnDetected: (d) => handleTurn(d),
  onHeadNodDetected: (d) => handleNod(d),
  onBrowRaised: (d) => handleBrow(d),
  onMouthOpened: (d) => handleMouth(d),
  onPoseChanged: (d) => handlePose(d),
  onDistanceChanged: (d) => handleDistance(d),
  onQualityChanged: (d) => handleQuality(d),
  onCaptureBlocked: (d) => showHint(d.reasons),
  onCaptureReady: (d) => detectorController.capturePhoto(),
  onFaceFrame: (frame) => handleRawFrame(frame),
  child: CameraPreview(cameraController),
)
```

The camera must deliver NV21 frames: `CameraController(..., imageFormatGroup: ImageFormatGroup.nv21)`.

## Photo capture

A liveness or enrolment flow usually ends with a photo that has to be good
enough for face matching. The package turns that into two pieces:

1. **Capture gates** (`CaptureReadyRecognizer`). Every frame is checked for
   face present, frontal pose, distance, brightness, sharpness, eyes open and
   (optionally) mouth closed. `onCaptureBlocked` reports the current
   `CaptureBlockReason`s whenever they change — an empty list means "all
   gates pass, hold still" — and `onCaptureReady` fires once after the gates
   have held for `captureSustainedDuration` (600 ms by default).
2. **`controller.capturePhoto()`**. Takes a full-resolution picture with the
   attached `CameraController` (the analysis stream is stopped and restarted
   around `takePicture()`, see `CaptureOptions.stopStreamWhileCapturing`)
   and post-processes it natively: EXIF orientation → optional mirror → crop
   around the last detected face (`marginFactor`, `aspectRatio`) → downscale
   to `targetShortSide` (never upscale) → JPEG → brightness/sharpness of the
   result.

```dart
final detectorController = FaceGestureDetectorController();

FaceGestureDetector(
  configuration: FaceGestureConfiguration(
    captureMaxYaw: 15,
    captureMinSharpness: 60,
    captureSustainedDuration: Duration(milliseconds: 600),
  ),
  cameraController: cameraController,
  controller: detectorController,
  onCaptureBlocked: (d) => setState(() => hint = d.reasons.join(', ')),
  onCaptureReady: (_) async {
    final photo = await detectorController.capturePhoto(
      options: const CaptureOptions(
        cropToFace: true,
        marginFactor: 0.6,
        aspectRatio: 0.75,      // 3:4 portrait
        targetShortSide: 1080,
        jpegQuality: 92,
        mirror: false,          // keep real geometry for biometrics
      ),
    );
    // photo.path, photo.width × photo.height, photo.faceRect (normalized,
    // upright), photo.quality.brightness / sharpness, photo.cropApplied
  },
  child: CameraPreview(cameraController),
);
```

Notes:

- **Resolution.** With `camera_android_camerax` the still image from
  `takePicture()` uses the same `ResolutionPreset` as the preview and the
  analysis stream: `high` gives 1280×720 photos, `veryHigh` 1920×1080.
  Pick the preset for the photo you need; the analysis stream (NV21 →
  MediaPipe) still runs at that size, so measure the frame rate on your
  device matrix.
- **Warm-up.** `startDetection()` loads the MediaPipe model and delegate
  before the image stream starts; on a low-end device this takes several
  seconds (4–7 s on a Samsung A04, where the GPU delegate falls back to
  the XNNPACK CPU delegate). No frames — and no `onCaptureReady` — arrive
  until then.
- **Timeout.** `CaptureOptions.timeout` (10 s) bounds `takePicture()` and
  the native processing. CameraX never answers `takePicture()` once the
  preview surface is gone (screen off, app backgrounded); the timeout
  surfaces that as a `TimeoutException` and the image stream restarts.
- The face box comes from the last analysed frame (raw sensor orientation)
  and is mapped to the upright picture with `mapSensorRectToUpright()`.
  The analysis stream and the still capture may use slightly different
  fields of view; `marginFactor` absorbs that.
- `mirror` defaults to `false`. Front-camera previews look mirrored, but
  the still image from `takePicture()` is not, and face-matching should
  compare real geometry.
- Sharpness is the variance of the Laplacian on a ~160-column subsample
  of the face region. Reference values from a Samsung A04 front camera: a
  texture-less scene (blank ceiling, no face) measures 8–40 on the live
  stream and 55–120 on the processed photo. `captureMinSharpness`
  defaults to 60 as a **provisional** value — calibrate it with real faces
  on your device matrix before relying on the `blurry` gate.

## 16 KB page size (Google Play)

Since 2025-11-01 Google Play requires apps targeting Android 15+ to support
16 KB memory pages. This package bundles MediaPipe `tasks-vision`
**0.10.26.1**, whose `libmediapipe_tasks_vision_jni.so` is aligned to
16 KB (0.10.21 and older were 4 KB-aligned and fail the check).

Consumer apps need:

- Android Gradle Plugin **8.5.1 or newer** (the example uses 8.11.1).
- `android.packaging.jniLibs.useLegacyPackaging = false` (default when
  `minSdk >= 23`; the example sets it explicitly).
- No other native dependency aligned to 4 KB. Verify a release build with
  `zipalign -c -P 16 -v 4 app-release.apk`, or by checking that every
  `PT_LOAD` segment of each `lib/arm64-v8a/*.so` has `p_align >= 0x4000`.

## Architecture

Five-layer stack following Flutter's gesture system analogy:

| Layer | Class | Role |
|-------|-------|------|
| 1 | `FaceGestureDetector` | Facade — callbacks → recognizer map |
| 2 | `RawFaceGestureDetector` | Lifecycle — stream, recognizer management |
| 3 | Recognizers (`BlinkRecognizer`, etc.) | Temporal gesture logic |
| 4 | `FaceGestureDetectorPlatform` | Platform interface |
| 5 | Native (Kotlin + MediaPipe) | Camera + ML processing |

See [doc/architecture.md](doc/architecture.md) for full details.

## Status

> **v0.3.0** — Face gesture detection, capture gates and full-resolution photo capture on Android; Google Play 16 KB compliant.

- [x] Data model with 52 blendshapes, landmarks, pose angles, frame size
- [x] Platform interface (MethodChannel + EventChannel + processFrame + processCapturedPhoto)
- [x] 11 recognizers with full test coverage
- [x] Layer 2 widget with frame routing, recognizer diff, controller, capture host
- [x] Layer 1 facade with callback-to-recognizer mapping
- [x] Native Android — MediaPipe Face Landmarker (LIVE_STREAM + GPU delegate), real brightness/sharpness metrics
- [x] Camera integration — `cameraController` parameter wires the full pipeline
- [x] Photo capture — `capturePhoto()` with native EXIF/crop/downscale/JPEG processing
- [x] Example app — live preview, gesture log, capture gates overlay, capture button / auto-capture
- [x] Release build — ProGuard rules, sensor orientation compensation, 16 KB page-size alignment
- [ ] Native iOS
