# Diagnosis: photo capture quality in 0.3.1

**Status:** analysis — no code changed. **Date:** 2026-11-07. **Applies to:** 0.3.1 (Android).

## 1. Context

0.3.0 added native photo capture (`capturePhoto`) and real quality metrics, so a host app can take an identity selfie automatically once the face is well framed. The selfie is later compared server-side against a reference photo of the same person (taken by staff with a rear camera) by a face verification model (SCRFD detector + MobileFaceNet embedding).

This document reviews the package against the first production photos taken with it: **60 selfies** from a pilot, with the reference photo of each person. A human reviewer inspected every pair and reported selfies that were blurry, shaken, partially cut or partially covered. The numbers below come from the stored JPEGs, measured offline with an independent detector (SCRFD 500M) and a Laplacian-variance sharpness on the face region resized to 160 px wide. They are aggregates; no image or personal data is included.

The host app followed the pattern the package encourages today:

1. evaluate each analyzed frame (`onFaceFrame`) against its own framing rules — face width 60–70 % of the visible width, face centre within 30–70 % horizontally and 25–60 % vertically, yaw/pitch ≤ 15°, brightness 0.25–0.80;
2. when the rules hold for 500 ms, run a **3-second countdown**;
3. call `capturePhoto(cropToFace: true, marginFactor: 1.4, aspectRatio: 0.75, targetShortSide: 1080)` with the camera at `ResolutionPreset.high`;
4. a manual fallback button calls `capturePhoto` with only "a face is present" as condition.

## 2. How `capturePhoto` works in 0.3.1

1. Remember `_lastFrame` — the last analyzed frame (1 of every 3 stream frames with the default `frameSkipCount: 2`).
2. Stop the image stream.
3. `CameraController.takePicture()` — a **new, separate exposure**, with its own latency.
4. Restart the image stream.
5. Native `PhotoProcessor`: apply EXIF orientation, mirror, **crop around the face box of `_lastFrame`**, downscale, re-encode as JPEG, measure brightness and sharpness of the result.
6. Return `CapturedPhoto` (path, size, brightness, sharpness, face rect, crop flag).

## 3. Findings

### F1 — No gate looks at the photo that is actually stored

All gates (in the package or in the host app) run on preview frames. The stored image is a different exposure taken after stopping the stream, and nothing measures the delay between the last good frame and the shutter. `CapturedPhoto.quality.sharpness` is returned but not judged, and when a crop is applied it is computed over the **whole crop** (hair, shoulders, background), not the face (`PhotoProcessor.process`, `sharpnessRegion = null` when `cropApplied`). With a fixed countdown in between, anything can happen after the last check.

**Evidence.** The stored selfies are the least sharp image in the flow: face sharpness p25 / median / p75 = **248 / 456 / 729**, against 670 / 1 050 / 1 550 for the reference photos. The three least sharp accepted selfies (49, 54, 108) include two that the reviewer flagged as blurry or shaken.

### F2 — There is no notion of stability

Neither the package nor the host app measures motion: no frame-to-frame displacement of the face box, no device motion. A face can stay inside the framing ranges while the phone shakes, and it can also be off-centre, blurry or have its eyes closed: the host app's rules do not check sharpness or eyes, and `CaptureReadyRecognizer` — which does check sharpness and eyes and has a sustained-duration timer — was not used.

### F3 — Per-frame sharpness exists but is uncalibrated

`FaceFrame.quality.sharpness` is measured inside the face box on every analyzed frame, which is the right place. The default `captureMinSharpness = 60` is documented as *provisional, not measured on faces*. Its scale (NV21 luma, subsampled to ~160 columns, same-spacing Laplacian) is not the scale of an offline measurement on the JPEG, so it cannot be calibrated from stored photos alone: the per-frame value must be recorded at capture time.

### F4 — The crop uses a stale face position, and the framing rules allow a cut face

Two separate mechanisms produce partially cut faces:

- **Stale box.** The crop is placed with `_lastFrame`'s face box, which predates the stream stop and the shutter latency. If the subject moves in between, the crop is shifted.
- **Inconsistent rules.** A face of width `w` (fraction of the frame) is fully inside only if its centre lies in `[w/2, 1 − w/2]`. With `w` up to 0.70 that is `[0.35, 0.65]`, but the centre rule allowed `[0.30, 0.70]`: an accepted frame could already have the face touching or crossing the edge.

**Evidence.** Position of the face in the stored selfies: centre x 0.32–0.64, centre y 0.45–0.69. Two selfies have the face touching the left edge (left = 0.00 and 0.01) and one touching the bottom (0.99); the reviewer had noted "the full face is not visible" in one of them. One stored selfie has **no detectable face** at all.

### F5 — The distance rule and the crop margin contradict each other

`marginFactor: 1.4` asks for a crop 2.4 × the face width (head and shoulders), which fits only if the face is ≤ 1 / 2.4 ≈ **42 %** of the frame width. The framing rule demanded 60–70 %. `computeCropRect` then clips the crop to the full frame width, so every selfie came out **720 × 960 with the face at 63 % of the width** (range 0.55–0.71): there is almost no margin, and any movement cuts the face (F4). The reference photos, stored uncropped, have the face at the same 63 % of the width, but at 1080 × 1920.

### F6 — Resolution differs between the two photos

The selfie camera ran at `ResolutionPreset.high` (720p) and the reference camera at `veryHigh` (1080p): **217 px vs 330 px** between the eyes (medians). The verification model aligns faces to 112 px, so both suffice for it, but the lower resolution leaves less headroom against blur and makes the two photos inconsistent.

### F7 — Camera metadata is thrown away

`PhotoProcessor` reads EXIF only for the orientation, then re-encodes the bitmap: **0 of 60 selfies and 0 of 60 reference photos keep any EXIF tag**. The values that explain motion blur — exposure time and ISO — are lost, together with aperture, focal length, white balance, flash and make/model. The package also does not report how long `takePicture` took or which frame the crop came from.

### F8 — Occlusion cannot be detected

`faceConfidence` is always 1.0 (MediaPipe's landmarker does not expose a detection score), and the landmarker places all 478 points even when part of the face is covered. Only the eye-blink blendshapes say something about the eyes. A hand, a phone or an object covering part of the face — reported by the reviewer in one selfie — passes every current check.

### F9 — Release hygiene

0.3.1 was published to pub.dev on 2026-10-13 from `fix/cerrar-motor-en-executor`. `main` is still at 0.3.0 and there is no `v0.3.1` tag.

## 4. Proposals (for decision)

| # | Change | Addresses |
|---|---|---|
| P1 | **Capture as soon as every gate holds, without a countdown.** Keep a short sustained window (`captureSustainedDuration`, ~300–500 ms) so that a single lucky frame does not trigger. | F1, F2 |
| P2 | **Stability gate.** New `CaptureBlockReason.unstable` based on the face box: centre displacement and size change between consecutive analyzed frames below a threshold during the sustained window. Optionally, device angular velocity from the gyroscope. | F2 |
| P3 | **Validate the stored photo.** Run detection on the still itself (MediaPipe in IMAGE mode), and reject it (or retry automatically) if there is no face, the face touches the border, the eyes are closed, or the face sharpness is below the threshold. Use that detection — not `_lastFrame` — for any crop and for `faceRect`. Alternative to evaluate: a short burst, keeping the sharpest face. | F1, F4 |
| P3b | **Alternative: the frame is the photo.** Encode the analyzed frame that passed the gates instead of calling `takePicture`. No shutter latency, and the measured quality *is* the stored quality. Cost: stream frames skip part of the still-image processing (noise reduction, HDR) and are limited to the stream resolution. Needs an experiment against P3. | F1, F4 |
| P4 | **Full frame by default.** Make `cropToFace: false` the documented default for verification use cases and keep the crop as an opt-in. When crop is used, reject options where the framing rules cannot fit the requested margin. | F4, F5 |
| P5 | **Document a consistent resolution.** Recommend `ResolutionPreset.veryHigh` for identity capture on both cameras, and report the resolution actually obtained (a front camera may fall back to a lower one). | F6 |
| P6 | **Return capture metadata.** Add `CapturedPhoto.metadata`: original EXIF (exposure time, ISO, f-number, focal length, white balance, flash, make, model, original size), shutter latency, time since the last good frame, camera description (lens, sensor orientation, preset) and the gate values of the last frame. Optionally write the EXIF back to the output JPEG. | F7, F3 |
| P7 | **Measure sharpness on the face** in the stored photo too (detected face region from P3, not the whole crop), and calibrate `captureMinSharpness` with values recorded by P6 on real devices. | F1, F3 |
| P8 | **Occlusion, in layers.** (a) Require eyes open (`captureRequireEyesOpen`) — already available. (b) In P3, use MediaPipe's face *detector* on the still, whose confidence does drop with occlusion, and expose it as `faceConfidence`. (c) Leave the final decision to the server: a face-image quality score (e.g. the verification model's detector score or a FIQA model) rejects the photo and asks for a new one. No layer is reliable alone; (b) and (c) need measurement. | F8 |
| P9 | Merge 0.3.1 into `main` and tag `v0.3.1`. Release later changes from `main`. | F9 |

Host-app guidance that follows from F4 and F5, independent of the package: the centre rule must depend on the face width (`cx ∈ [w/2 + m, 1 − w/2 − m]`), and the distance rule must be consistent with any crop margin.

## 5. Suggested order

1. **P9**, so that work starts from the released code.
2. **P6**: without metadata, every new threshold (sharpness, stability) is calibrated blind.
3. **P1 + P2 + P3** (or P3b after a short comparison): the defects the reviewer saw.
4. **P4, P5, P7, P8**.

## 6. Open questions

- What is the shutter latency of `takePicture` on low-end devices with the stream stopped and restarted? P6 measures it.
- Does a stream frame at 1080p (P3b) give a face as sharp as a still on the target devices?
- Which stability threshold separates hand tremor from real movement at 10–15 analyzed frames per second?
- Does dropping the crop (P4) change the verification scores? Uncropped photos are larger; the model detects and aligns the face itself, but the change should be checked against the current threshold.
