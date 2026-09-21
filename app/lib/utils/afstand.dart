import 'dart:math';

import 'package:maplibre_gl/maplibre_gl.dart';

/// Hemelsbrede afstand in meters (haversine).
double meters(LatLng a, LatLng b) {
  const straal = 6371000.0;
  double rad(double graden) => graden * pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLon = rad(b.longitude - a.longitude);
  final h =
      pow(sin(dLat / 2), 2) +
      cos(rad(a.latitude)) * cos(rad(b.latitude)) * pow(sin(dLon / 2), 2);
  return 2 * straal * asin(sqrt(h));
}
