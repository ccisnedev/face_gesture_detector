/// Face Gesture Detector — a Flutter widget that translates camera frames
/// and MediaPipe facial landmarks into high-level semantic callbacks.
///
/// Import this barrel file to access all public types:
/// ```dart
/// import 'package:face_gesture_detector/face_gesture_detector.dart';
/// ```
library;

export 'src/configuration/face_gesture_configuration.dart';

export 'src/controller/face_gesture_detector_controller.dart';

export 'src/model/captured_photo.dart';
export 'src/model/face_blendshape.dart';
export 'src/model/face_frame.dart';
export 'src/model/face_landmark.dart';
export 'src/model/image_quality_metrics.dart';
export 'src/model/pose_angles.dart';

// Details objects — one per callback family
export 'src/model/details/blink_details.dart';
export 'src/model/details/brow_details.dart';
export 'src/model/details/capture_ready_details.dart';
export 'src/model/details/distance_details.dart';
export 'src/model/details/face_detected_details.dart';
export 'src/model/details/head_nod_details.dart';
export 'src/model/details/head_turn_details.dart';
export 'src/model/details/mouth_details.dart';
export 'src/model/details/pose_details.dart';
export 'src/model/details/quality_details.dart';
export 'src/model/details/smile_details.dart';

// Platform
export 'src/platform/face_detection_options.dart';
export 'src/platform/face_gesture_detector_platform_interface.dart';
export 'src/platform/method_channel_face_gesture_detector.dart';

// Recognizer
export 'src/recognizer/blink_recognizer.dart';
export 'src/recognizer/brow_recognizer.dart';
export 'src/recognizer/capture_ready_recognizer.dart';
export 'src/recognizer/face_gesture_recognizer.dart';
export 'src/recognizer/face_gesture_recognizer_factory.dart';
export 'src/recognizer/face_presence_recognizer.dart';
export 'src/recognizer/head_nod_recognizer.dart';
export 'src/recognizer/head_turn_recognizer.dart';
export 'src/recognizer/mouth_recognizer.dart';
export 'src/recognizer/pose_recognizer.dart';
export 'src/recognizer/quality_gate_recognizer.dart';
export 'src/recognizer/raw_frame_recognizer.dart';
export 'src/recognizer/smile_recognizer.dart';

// Utilities
export 'src/util/rect_mapping.dart';

// Widget
export 'src/widget/camera_capture_adapter.dart';
export 'src/widget/face_gesture_detector.dart';
export 'src/widget/raw_face_gesture_detector.dart';
