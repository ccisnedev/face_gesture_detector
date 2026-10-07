import 'dart:ui';

import 'package:face_gesture_detector/src/model/face_blendshape.dart';
import 'package:face_gesture_detector/src/model/face_landmark.dart';
import 'package:face_gesture_detector/src/model/image_quality_metrics.dart';
import 'package:face_gesture_detector/src/model/pose_angles.dart';

/// Facial data from a single camera frame processed by the native pipeline.
///
/// Produced by the native layer at ~10–15fps (after frame dropping).
/// Consumed by FaceGestureRecognizers in Dart.
/// Approximate size: ~2KB per frame (without landmarks), ~10KB with landmarks.
class FaceFrame {
  final Duration timestamp;
  final bool isFaceDetected;
  final double faceConfidence;

  /// Bounding box of the face in **pixels of the raw camera frame**
  /// (sensor orientation, not rotated). Normalize with [frameWidth] and
  /// [frameHeight].
  final Rect faceBoundingBox;
  final PoseAngles poseAngles;
  final Map<FaceBlendshape, double> blendshapes;
  final List<FaceLandmark>? landmarks;
  final ImageQualityMetrics quality;

  /// Size of the raw camera frame the box refers to. `0` when unknown
  /// (frames built by hand or by an older native layer).
  final int frameWidth;
  final int frameHeight;

  const FaceFrame({
    required this.timestamp,
    required this.isFaceDetected,
    required this.faceConfidence,
    required this.faceBoundingBox,
    required this.poseAngles,
    required this.blendshapes,
    required this.landmarks,
    required this.quality,
    this.frameWidth = 0,
    this.frameHeight = 0,
  });

  /// Deserializes a FaceFrame from the Map sent by the native platform channel.
  ///
  /// The map keys match the Kotlin serialization in FaceLandmarkerEngine.
  factory FaceFrame.fromMap(Map<String, dynamic> map) {
    final bbox = Map<String, dynamic>.from(map['faceBoundingBox'] as Map);
    final pose = Map<String, dynamic>.from(map['poseAngles'] as Map);
    final qualityMap = Map<String, dynamic>.from(map['quality'] as Map);
    final rawBlendshapes = Map<String, dynamic>.from(map['blendshapes'] as Map);
    final rawLandmarks = map['landmarks'] as List<dynamic>?;

    return FaceFrame(
      timestamp: Duration(milliseconds: map['timestamp'] as int),
      isFaceDetected: map['isFaceDetected'] as bool,
      faceConfidence: (map['faceConfidence'] as num).toDouble(),
      faceBoundingBox: Rect.fromLTWH(
        (bbox['left'] as num).toDouble(),
        (bbox['top'] as num).toDouble(),
        (bbox['width'] as num).toDouble(),
        (bbox['height'] as num).toDouble(),
      ),
      poseAngles: PoseAngles(
        pitch: (pose['pitch'] as num).toDouble(),
        yaw: (pose['yaw'] as num).toDouble(),
        roll: (pose['roll'] as num).toDouble(),
      ),
      blendshapes: _parseBlendshapes(rawBlendshapes),
      landmarks: rawLandmarks != null ? _parseLandmarks(rawLandmarks) : null,
      quality: ImageQualityMetrics(
        brightness: (qualityMap['brightness'] as num).toDouble(),
        sharpness: (qualityMap['sharpness'] as num).toDouble(),
      ),
      frameWidth: (map['frameWidth'] as num?)?.toInt() ?? 0,
      frameHeight: (map['frameHeight'] as num?)?.toInt() ?? 0,
    );
  }

  /// Maps blendshape name strings from native to FaceBlendshape enum values.
  static Map<FaceBlendshape, double> _parseBlendshapes(
    Map<String, dynamic> raw,
  ) {
    final byName = {for (final v in FaceBlendshape.values) v.name: v};
    return {
      for (final entry in raw.entries)
        if (byName.containsKey(entry.key))
          byName[entry.key]!: (entry.value as num).toDouble(),
    };
  }

  static List<FaceLandmark> _parseLandmarks(List<dynamic> raw) {
    return [
      for (final point in raw)
        () {
          final m = Map<String, dynamic>.from(point as Map);
          return FaceLandmark(
            x: (m['x'] as num).toDouble(),
            y: (m['y'] as num).toDouble(),
            z: (m['z'] as num).toDouble(),
          );
        }(),
    ];
  }
}
