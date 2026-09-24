import 'dart:math';

import 'package:maplibre_gl/maplibre_gl.dart';

import '../navigation/route_tracker.dart';

/// A gantry with MSI signs on the route: how far along the route, and per lane
/// (left to right) what it shows. Codes as the importer provides them: "70"
/// (advisory), "70r" (mandatory, red ring), "x" (lane closed), "<" / ">"
/// (merge left/right), "open", "end" or "" (blank).
typedef Gantry = ({double along, List<String> perLane});

/// The gantries from [layer] (`kind: msi`) above your carriageway: within
/// [maxDistance] of the route, and in the same direction (the other side of the
/// motorway is close by too). If two hang at the same place along the route
/// (main and parallel carriageway), the nearest counts. In order along the
/// route.
///
/// A gantry's point is usually on the carriageway's line (0-2 m), sometimes up
/// to ~25 m off it.
List<Gantry> gantriesOnRoute(
  RouteTracker tracker,
  Map<String, dynamic>? layer, {
  double maxDistance = 35,
  double maxAngle = 45,
}) {
  final route = tracker.route.points;
  if (layer == null || route.length < 2) return const [];
  var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
  for (final p in route) {
    south = min(south, p.latitude);
    north = max(north, p.latitude);
    west = min(west, p.longitude);
    east = max(east, p.longitude);
  }
  const margin = 0.001; // ~100 m
  final found = <({Gantry gantry, double distance})>[];
  for (final feature in (layer['features'] as List? ?? const [])) {
    if (feature is! Map) continue;
    final props = feature['properties'];
    final geometry = feature['geometry'];
    if (props is! Map ||
        props['kind'] != 'msi' ||
        geometry is! Map ||
        geometry['type'] != 'Point') {
      continue;
    }
    final c = (geometry['coordinates'] as List).cast<num>();
    final point = LatLng(c[1].toDouble(), c[0].toDouble());
    if (point.latitude < south - margin ||
        point.latitude > north + margin ||
        point.longitude < west - margin ||
        point.longitude > east + margin) {
      continue;
    }
    final position = tracker.locate(point);
    final heading = props['bearing'];
    if (position.distance > maxDistance ||
        heading is! num ||
        angleDiff(heading.toDouble(), position.heading) > maxAngle) {
      continue;
    }
    found.add((
      gantry: (
        along: position.along,
        perLane: [for (final s in (props['lanes'] as List? ?? const [])) '$s'],
      ),
      distance: position.distance,
    ));
  }
  found.sort((a, b) => a.gantry.along.compareTo(b.gantry.along));
  final out = <({Gantry gantry, double distance})>[];
  for (final g in found) {
    if (out.isNotEmpty && g.gantry.along - out.last.gantry.along < 60) {
      if (g.distance < out.last.distance) out[out.length - 1] = g;
      continue;
    }
    out.add(g);
  }
  return [for (final g in out) g.gantry];
}

/// The mandatory speed (red ring) of the MSI signs you're driving under now:
/// that of the last gantry passed, up to [validUntil] meters after it. A speed
/// above the road applies until the next gantry; if that shows nothing (or
/// "end"), it stops. If it differs per lane, the lowest. Null if none applies.
/// An advisory (without a red ring) isn't a limit.
int? msiLimit(List<Gantry> gantries, double along, {double validUntil = 3000}) {
  Gantry? latest;
  for (final gantry in gantries) {
    if (gantry.along > along + 5) break;
    latest = gantry;
  }
  if (latest == null || along - latest.along > validUntil) return null;
  int? lowest;
  for (final lane in latest.perLane) {
    if (!lane.endsWith('r')) continue;
    final kmh = int.tryParse(lane.substring(0, lane.length - 1));
    if (kmh != null && (lowest == null || kmh < lowest)) lowest = kmh;
  }
  return lowest;
}

/// The next gantry within [ahead] meters that shows something, and how far
/// away it is.
({double ahead, List<String> perLane})? nextGantry(
  List<Gantry> gantries,
  double along, {
  double ahead = 1500,
}) {
  for (final gantry in gantries) {
    if (gantry.along <= along + 5) continue;
    if (gantry.along - along > ahead) return null;
    if (gantry.perLane.any((s) => s.isNotEmpty)) {
      return (ahead: gantry.along - along, perLane: gantry.perLane);
    }
    // A blank gantry: the restrictions end there; what comes after only counts
    // once you've passed it.
    return null;
  }
  return null;
}
