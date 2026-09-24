import 'dart:math';

import 'package:maplibre_gl/maplibre_gl.dart';

/// Straight-line distance in meters (haversine).
double meters(LatLng a, LatLng b) {
  const radius = 6371000.0;
  double rad(double degrees) => degrees * pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLon = rad(b.longitude - a.longitude);
  final h =
      pow(sin(dLat / 2), 2) +
      cos(rad(a.latitude)) * cos(rad(b.latitude)) * pow(sin(dLon / 2), 2);
  return 2 * radius * asin(sqrt(h));
}

/// Meters from [p] to the nearest point on [line] (flat projection around [p]:
/// accurate to the centimeter over a few kilometers).
double metersToLine(LatLng p, List<LatLng> line) {
  if (line.isEmpty) return double.infinity;
  if (line.length == 1) return meters(p, line.first);
  final cosine = cos(p.latitude * pi / 180);
  var best = double.infinity;
  for (var i = 0; i < line.length - 1; i++) {
    final ax = (line[i].longitude - p.longitude) * cosine * 111320;
    final ay = (line[i].latitude - p.latitude) * 110574;
    final bx = (line[i + 1].longitude - p.longitude) * cosine * 111320;
    final by = (line[i + 1].latitude - p.latitude) * 110574;
    final dx = bx - ax, dy = by - ay;
    final squared = dx * dx + dy * dy;
    final t = squared == 0
        ? 0.0
        : ((-ax * dx - ay * dy) / squared).clamp(0.0, 1.0);
    final x = ax + t * dx, y = ay + t * dy;
    best = min(best, x * x + y * y);
  }
  return sqrt(best);
}

/// The heading from [a] to [b] in degrees (0 = north), clockwise.
double headingBetween(LatLng a, LatLng b) {
  final f1 = a.latitude * pi / 180, f2 = b.latitude * pi / 180;
  final dl = (b.longitude - a.longitude) * pi / 180;
  final y = sin(dl) * cos(f2);
  final x = cos(f1) * sin(f2) - sin(f1) * cos(f2) * cos(dl);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}
