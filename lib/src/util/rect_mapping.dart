import 'dart:ui';

/// Maps a rectangle expressed in the raw camera frame (normalized 0..1,
/// as delivered by `CameraController.startImageStream`) to the upright
/// frame the user sees and `takePicture()` produces after EXIF orientation.
///
/// [sensorOrientation] is `CameraDescription.sensorOrientation`: the
/// clockwise rotation, in degrees, that the raw frame needs to be upright.
/// Only multiples of 90 are meaningful; any other value returns [rect]
/// unchanged.
Rect mapSensorRectToUpright(Rect rect, int sensorOrientation) {
  final rotation = ((sensorOrientation % 360) + 360) % 360;
  if (rotation == 0 || rotation % 90 != 0) return rect;

  Offset map(Offset p) {
    switch (rotation) {
      case 90:
        return Offset(1.0 - p.dy, p.dx);
      case 180:
        return Offset(1.0 - p.dx, 1.0 - p.dy);
      case 270:
        return Offset(p.dy, 1.0 - p.dx);
      default:
        return p;
    }
  }

  final corners = [
    map(rect.topLeft),
    map(rect.topRight),
    map(rect.bottomLeft),
    map(rect.bottomRight),
  ];
  var minX = corners.first.dx;
  var maxX = corners.first.dx;
  var minY = corners.first.dy;
  var maxY = corners.first.dy;
  for (final c in corners.skip(1)) {
    if (c.dx < minX) minX = c.dx;
    if (c.dx > maxX) maxX = c.dx;
    if (c.dy < minY) minY = c.dy;
    if (c.dy > maxY) maxY = c.dy;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}
