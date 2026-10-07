import 'package:flutter/foundation.dart';

import 'package:face_gesture_detector/src/model/captured_photo.dart';
import 'package:face_gesture_detector/src/model/face_frame.dart';

/// What a [FaceGestureDetectorController] needs from the widget it is
/// attached to in order to capture photos.
///
/// Implemented by `RawFaceGestureDetectorState`. Apps never implement it.
abstract class FaceCaptureHost {
  /// The last frame dispatched by the native pipeline, if any.
  FaceFrame? get lastFrame;

  /// Takes and post-processes a photo. See
  /// [FaceGestureDetectorController.capturePhoto].
  Future<CapturedPhoto> capturePhoto(CaptureOptions options);
}

/// Imperative controller for [RawFaceGestureDetector].
///
/// Allows pausing, resuming and resetting the detection pipeline, and —
/// once attached to a mounted detector with a camera — capturing a
/// full-resolution photo with [capturePhoto].
///
/// Uses [ChangeNotifier] so the widget can react to pause/resume/reset;
/// capture state changes do **not** notify (they would reset recognizers).
class FaceGestureDetectorController extends ChangeNotifier {
  bool _isPaused = false;
  bool _isCapturing = false;
  FaceCaptureHost? _host;

  /// Whether frame dispatch to recognizers is paused.
  bool get isPaused => _isPaused;

  /// Whether a [capturePhoto] call is in progress.
  bool get isCapturing => _isCapturing;

  /// Whether a detector widget is currently attached.
  bool get isAttached => _host != null;

  /// The last frame seen by the attached detector, if any.
  FaceFrame? get lastFrame => _host?.lastFrame;

  /// Pauses frame dispatch. Recognizers stop receiving frames.
  void pause() {
    if (!_isPaused) {
      _isPaused = true;
      notifyListeners();
    }
  }

  /// Resumes frame dispatch after a pause.
  void resume() {
    if (_isPaused) {
      _isPaused = false;
      notifyListeners();
    }
  }

  /// Resets all recognizers to their initial state.
  void reset() {
    notifyListeners();
  }

  /// Takes a full-resolution picture with the attached camera and returns
  /// the processed result (oriented, optionally mirrored, cropped around
  /// the last detected face, downscaled, JPEG).
  ///
  /// Frame dispatch is suspended while the picture is taken so recognizers
  /// do not fire mid-capture. Throws [StateError] when no detector with a
  /// camera is attached, or when a capture is already running.
  Future<CapturedPhoto> capturePhoto({
    CaptureOptions options = const CaptureOptions(),
  }) async {
    final host = _host;
    if (host == null) {
      throw StateError(
        'capturePhoto() requires the controller to be attached to a mounted '
        'FaceGestureDetector with a cameraController.',
      );
    }
    if (_isCapturing) {
      throw StateError('A capture is already in progress.');
    }
    _isCapturing = true;
    try {
      return await host.capturePhoto(options);
    } finally {
      _isCapturing = false;
    }
  }

  /// Called by the detector widget when it mounts. Not for app use.
  void attach(FaceCaptureHost host) {
    _host = host;
  }

  /// Called by the detector widget when it unmounts. Not for app use.
  void detach(FaceCaptureHost host) {
    if (identical(_host, host)) _host = null;
  }
}
