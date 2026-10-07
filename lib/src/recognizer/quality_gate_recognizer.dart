import 'package:face_gesture_detector/src/configuration/face_gesture_configuration.dart';
import 'package:face_gesture_detector/src/model/details/distance_details.dart';
import 'package:face_gesture_detector/src/model/details/quality_details.dart';
import 'package:face_gesture_detector/src/model/face_frame.dart';
import 'package:face_gesture_detector/src/model/face_landmark.dart';
import 'package:face_gesture_detector/src/recognizer/face_gesture_recognizer.dart';

/// Callback signatures for quality gate events.
typedef QualityChangedCallback = void Function(QualityDetails details);
typedef DistanceChangedCallback = void Function(DistanceDetails details);

/// Recognizes changes in image quality and face distance.
///
/// Monitors brightness/sharpness metrics and the face bounding box ratio
/// relative to the frame. Only fires callbacks on category **changes**,
/// not on every frame — reducing noise for the consumer.
class QualityGateRecognizer extends FaceGestureRecognizer {
  final QualityChangedCallback onQualityChanged;
  final DistanceChangedCallback onDistanceChanged;
  final double frameWidth;
  final double frameHeight;

  DistanceCategory? _previousDistanceCategory;
  bool _hasEmittedQuality = false;

  QualityGateRecognizer({
    required FaceGestureConfiguration configuration,
    required this.frameWidth,
    required this.frameHeight,
    required this.onQualityChanged,
    required this.onDistanceChanged,
  }) : super(configuration);

  @override
  void addFaceFrame(FaceFrame frame) {
    _emitQualityIfNeeded(frame);
    _emitDistanceIfCategoryChanged(frame);
  }

  void _emitQualityIfNeeded(FaceFrame frame) {
    // Emit quality on every frame that passes — the consumer decides
    // when metrics are sufficient. First-frame emission establishes baseline.
    if (!_hasEmittedQuality || true) {
      // Quality is always reported so the app can track real-time metrics.
      _hasEmittedQuality = true;
      final isSufficient =
          frame.quality.brightness >= configuration.captureMinBrightness &&
          frame.quality.brightness <= configuration.captureMaxBrightness &&
          frame.quality.sharpness >= configuration.captureMinSharpness;
      onQualityChanged(
        QualityDetails(
          metrics: frame.quality,
          isSufficientForCapture: isSufficient,
        ),
      );
    }
  }

  void _emitDistanceIfCategoryChanged(FaceFrame frame) {
    final ratio = _boundingBoxRatio(frame);
    final category = _classifyDistance(ratio);

    if (category != _previousDistanceCategory) {
      _previousDistanceCategory = category;
      onDistanceChanged(
        DistanceDetails(category: category, boundingBoxRatio: ratio),
      );
    }
  }

  double _boundingBoxRatio(FaceFrame frame) {
    final bboxArea = frame.faceBoundingBox.width * frame.faceBoundingBox.height;
    // Prefer the real frame size reported by the native layer; fall back
    // to the configured dimensions for hand-built frames.
    final frameArea = frame.frameWidth > 0 && frame.frameHeight > 0
        ? (frame.frameWidth * frame.frameHeight).toDouble()
        : frameWidth * frameHeight;
    if (frameArea == 0) return 0;
    return bboxArea / frameArea;
  }

  DistanceCategory _classifyDistance(double ratio) {
    if (ratio < configuration.minDistanceRatio) return DistanceCategory.tooFar;
    if (ratio > configuration.maxDistanceRatio) {
      return DistanceCategory.tooClose;
    }
    return DistanceCategory.optimal;
  }

  @override
  void reset() {
    _previousDistanceCategory = null;
    _hasEmittedQuality = false;
  }

  @override
  void dispose() {
    // No resources to release.
  }
}
