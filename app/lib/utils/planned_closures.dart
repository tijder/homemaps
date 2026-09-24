import 'dart:math';

import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/route.dart';
import 'distance.dart';

/// A planned closure on a route, with the window in which it affects your
/// trip.
typedef ClosureOnRoute = ({DateTime from, DateTime? until});

/// Which planned closures from [layer] are on [route] while you drive it (from
/// [departure] to arrival, with an hour of slack). Valhalla can't route around
/// a closure in the future; this is the warning.
///
/// "On the route": at least two of the closure's three points (start, middle,
/// end) are within 20 m of the route line. First a rough bounding box around
/// the route, otherwise it gets slow for thousands of closures.
List<ClosureOnRoute> closuresOnRoute(
  RouteOption route,
  Map<String, dynamic> layer,
  DateTime departure,
) {
  if (route.points.length < 2) return const [];
  final end = departure.add(Duration(seconds: route.seconds.round() + 3600));
  var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
  for (final p in route.points) {
    south = min(south, p.latitude);
    north = max(north, p.latitude);
    west = min(west, p.longitude);
    east = max(east, p.longitude);
  }
  const margin = 0.001; // ~100 m
  bool inside(LatLng p) =>
      p.latitude >= south - margin &&
      p.latitude <= north + margin &&
      p.longitude >= west - margin &&
      p.longitude <= east + margin;

  final out = <ClosureOnRoute>[];
  for (final feature in (layer['features'] as List? ?? const [])) {
    if (feature is! Map) continue;
    final props = (feature['properties'] as Map?) ?? const {};
    final window = _overlap(props['windows'], departure, end);
    if (window == null) continue;
    final line = _line(feature['geometry']);
    if (line.length < 2) continue;
    final probes = [line.first, line[line.length ~/ 2], line.last];
    if (!probes.any(inside)) continue;
    final touching = probes.where((p) => metersToLine(p, route.points) < 20);
    if (touching.length >= 2) out.add(window);
  }
  out.sort((a, b) => a.from.compareTo(b.from));
  return out;
}

ClosureOnRoute? _overlap(Object? windows, DateTime from, DateTime until) {
  if (windows is! List) return null;
  for (final window in windows) {
    if (window is! List || window.isEmpty) continue;
    final begin = DateTime.tryParse(window[0] as String? ?? '');
    final windowEnd = window.length > 1 && window[1] is String
        ? DateTime.tryParse(window[1] as String)
        : null;
    if (begin == null) continue;
    if (begin.isAfter(until) ||
        (windowEnd != null && windowEnd.isBefore(from))) {
      continue;
    }
    return (from: begin, until: windowEnd);
  }
  return null;
}

List<LatLng> _line(Object? geometry) {
  if (geometry is! Map) return const [];
  LatLng point(Object? c) {
    final l = (c as List).cast<num>();
    return LatLng(l[1].toDouble(), l[0].toDouble());
  }

  return switch (geometry['type']) {
    'LineString' => [for (final c in geometry['coordinates'] as List) point(c)],
    'MultiLineString' => [
      for (final part in geometry['coordinates'] as List)
        for (final c in part as List) point(c),
    ],
    _ => const [],
  };
}
