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

/// Meters van [p] tot de dichtstbijzijnde plek op [lijn] (platte projectie
/// rond [p]: op een paar kilometer op de centimeter goed).
double metersTotLijn(LatLng p, List<LatLng> lijn) {
  if (lijn.isEmpty) return double.infinity;
  if (lijn.length == 1) return meters(p, lijn.first);
  final kos = cos(p.latitude * pi / 180);
  var beste = double.infinity;
  for (var i = 0; i < lijn.length - 1; i++) {
    final ax = (lijn[i].longitude - p.longitude) * kos * 111320;
    final ay = (lijn[i].latitude - p.latitude) * 110574;
    final bx = (lijn[i + 1].longitude - p.longitude) * kos * 111320;
    final by = (lijn[i + 1].latitude - p.latitude) * 110574;
    final dx = bx - ax, dy = by - ay;
    final kwadraat = dx * dx + dy * dy;
    final t = kwadraat == 0
        ? 0.0
        : ((-ax * dx - ay * dy) / kwadraat).clamp(0.0, 1.0);
    final x = ax + t * dx, y = ay + t * dy;
    beste = min(beste, x * x + y * y);
  }
  return sqrt(beste);
}
