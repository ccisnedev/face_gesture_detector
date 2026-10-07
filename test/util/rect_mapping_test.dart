import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:face_gesture_detector/face_gesture_detector.dart';

void main() {
  group('mapSensorRectToUpright', () {
    // A box near the top-left of the raw frame: x 0.1..0.3, y 0.2..0.6
    final rect = Rect.fromLTWH(0.1, 0.2, 0.2, 0.4);

    Matcher closeToRect(Rect expected) => predicate<Rect>(
      (r) =>
          (r.left - expected.left).abs() < 1e-9 &&
          (r.top - expected.top).abs() < 1e-9 &&
          (r.width - expected.width).abs() < 1e-9 &&
          (r.height - expected.height).abs() < 1e-9,
      'close to $expected',
    );

    test('0° returns the same rect', () {
      expect(mapSensorRectToUpright(rect, 0), same(rect));
    });

    test('90° clockwise: (x, y) → (1 - y, x)', () {
      // x' spans 1-0.6..1-0.2 = 0.4..0.8 ; y' spans 0.1..0.3
      expect(
        mapSensorRectToUpright(rect, 90),
        closeToRect(Rect.fromLTWH(0.4, 0.1, 0.4, 0.2)),
      );
    });

    test('180°: (x, y) → (1 - x, 1 - y)', () {
      // x' 0.7..0.9 ; y' 0.4..0.8
      expect(
        mapSensorRectToUpright(rect, 180),
        closeToRect(Rect.fromLTWH(0.7, 0.4, 0.2, 0.4)),
      );
    });

    test('270° clockwise: (x, y) → (y, 1 - x)', () {
      // x' 0.2..0.6 ; y' 1-0.3..1-0.1 = 0.7..0.9
      expect(
        mapSensorRectToUpright(rect, 270),
        closeToRect(Rect.fromLTWH(0.2, 0.7, 0.4, 0.2)),
      );
    });

    test('negative and >360 orientations are normalized', () {
      expect(
        mapSensorRectToUpright(rect, -90),
        closeToRect(mapSensorRectToUpright(rect, 270)),
      );
      expect(
        mapSensorRectToUpright(rect, 450),
        closeToRect(mapSensorRectToUpright(rect, 90)),
      );
    });

    test('non-multiples of 90 are returned unchanged', () {
      expect(mapSensorRectToUpright(rect, 45), same(rect));
    });

    test('corner mapping keeps the rect inside the unit square', () {
      final full = Rect.fromLTWH(0, 0, 1, 1);
      for (final o in [90, 180, 270]) {
        expect(mapSensorRectToUpright(full, o), closeToRect(full));
      }
    });
  });
}
