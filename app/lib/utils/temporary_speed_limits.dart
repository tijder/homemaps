import 'dart:math';

import 'package:maplibre_gl/maplibre_gl.dart';

/// The temporary speed limit (km/h) per stretch of [route]: element i belongs
/// to the stretch from point i to i+1, null where none applies. From the
/// traffic layer (`kind: speed_limit`, for roadworks or an event; see the
/// importer).
///
/// A stretch is covered if its midpoint is within [maxDistance] of such a line
/// and the line runs the same way there (within [maxAngle]): the line has a
/// driving direction, and the carriageway on the other side of the motorway is
/// close by too. If two overlap, the lowest counts.
List<int?> temporarySpeedLimits(
  List<LatLng> route,
  Map<String, dynamic>? layer, {
  double maxDistance = 15,
  double maxAngle = 45,
}) {
  final perStretch = List<int?>.filled(max(0, route.length - 1), null);
  if (layer == null || perStretch.isEmpty) return perStretch;
  final bounds = _BoundingBox.around(route, 0.001); // ~100 m
  final centers = [
    for (var i = 0; i < route.length - 1; i++)
      LatLng(
        (route[i].latitude + route[i + 1].latitude) / 2,
        (route[i].longitude + route[i + 1].longitude) / 2,
      ),
  ];
  // The midpoints in cells of ~500 m: a restriction is short, and there are
  // thousands in the country. This way each one only looks at nearby stretches.
  final cells = <int, List<int>>{};
  for (final (i, m) in centers.indexed) {
    (cells[_cellOf(m.latitude, m.longitude)] ??= []).add(i);
  }
  for (final feature in (layer['features'] as List? ?? const [])) {
    if (feature is! Map) continue;
    final props = feature['properties'];
    final kmh = props is Map ? props['kph'] : null;
    if (props is! Map || props['kind'] != 'speed_limit' || kmh is! num) {
      continue;
    }
    for (final line in _lines(feature['geometry'])) {
      if (line.length < 2) continue;
      final box = _BoundingBox.around(line, 0.0003); // ~30 m
      if (!box.overlaps(bounds)) continue;
      for (final i in box.cells().expand((v) => cells[v] ?? const <int>[])) {
        final m = centers[i];
        if (!box.contains(m)) continue;
        final position = _nearest(m, line);
        // Past the start or end of the line: the road continues there, but the
        // restriction doesn't.
        if (position.distance > maxDistance || position.passed) continue;
        final heading = _heading(route[i], route[i + 1], m);
        if (_angleDiff(heading, position.heading) > maxAngle) continue;
        final value = kmh.round();
        if (perStretch[i] == null || value < perStretch[i]!) {
          perStretch[i] = value;
        }
      }
    }
  }
  return perStretch;
}

List<List<LatLng>> _lines(Object? geometry) {
  if (geometry is! Map) return const [];
  List<LatLng> line(Object? coordinates) => [
    for (final c in (coordinates as List? ?? const []))
      if (c is List && c.length >= 2)
        LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
  ];
  return switch (geometry['type']) {
    'LineString' => [line(geometry['coordinates'])],
    'MultiLineString' => [
      for (final part in (geometry['coordinates'] as List? ?? const []))
        line(part),
    ],
    _ => const [],
  };
}

class _BoundingBox {
  _BoundingBox(this.south, this.north, this.west, this.east);

  factory _BoundingBox.around(List<LatLng> points, double margin) {
    var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
    for (final p in points) {
      south = min(south, p.latitude);
      north = max(north, p.latitude);
      west = min(west, p.longitude);
      east = max(east, p.longitude);
    }
    return _BoundingBox(
      south - margin,
      north + margin,
      west - margin,
      east + margin,
    );
  }

  final double south, north, west, east;

  bool contains(LatLng p) =>
      p.latitude >= south &&
      p.latitude <= north &&
      p.longitude >= west &&
      p.longitude <= east;

  bool overlaps(_BoundingBox b) =>
      south <= b.north && north >= b.south && west <= b.east && east >= b.west;

  Iterable<int> cells() sync* {
    for (
      var r = (south / _cellSize).floor();
      r <= (north / _cellSize).floor();
      r++
    ) {
      for (
        var k = (west / _cellSize).floor();
        k <= (east / _cellSize).floor();
        k++
      ) {
        yield r * 100000 + k;
      }
    }
  }
}

const _cellSize = 0.005; // degrees, ~500 m

int _cellOf(double lat, double lon) =>
    (lat / _cellSize).floor() * 100000 + (lon / _cellSize).floor();

/// Flat around [p]: accurate to the centimeter over a few kilometers.
({double x, double y}) _flatten(LatLng q, LatLng p) => (
  x: (q.longitude - p.longitude) * cos(p.latitude * pi / 180) * 111320,
  y: (q.latitude - p.latitude) * 110574,
);

/// The distance from [p] to [line], the line's heading at that spot, and
/// whether that spot is the start or end of the line while [p] lies beyond it.
({double distance, double heading, bool passed}) _nearest(
  LatLng p,
  List<LatLng> line,
) {
  var best = (distance: double.infinity, heading: 0.0, passed: false);
  for (var i = 0; i < line.length - 1; i++) {
    final a = _flatten(line[i], p), b = _flatten(line[i + 1], p);
    final dx = b.x - a.x, dy = b.y - a.y;
    final squared = dx * dx + dy * dy;
    if (squared == 0) continue;
    final raw = (-a.x * dx - a.y * dy) / squared;
    final t = raw.clamp(0.0, 1.0);
    final x = a.x + t * dx, y = a.y + t * dy;
    final distance = sqrt(x * x + y * y);
    if (distance < best.distance) {
      best = (
        distance: distance,
        heading: (atan2(dx, dy) * 180 / pi + 360) % 360,
        passed: (i == 0 && raw < 0) || (i == line.length - 2 && raw > 1),
      );
    }
  }
  return best;
}

double _heading(LatLng a, LatLng b, LatLng origin) {
  final pa = _flatten(a, origin), pb = _flatten(b, origin);
  return (atan2(pb.x - pa.x, pb.y - pa.y) * 180 / pi + 360) % 360;
}

double _angleDiff(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}
