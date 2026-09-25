import 'dart:math';

import 'package:maplibre_gl/maplibre_gl.dart';

import '../navigation/route_tracker.dart';

/// What checks your speed or the red light (OSM, via the importer's
/// `/enforcement`).
enum CameraKind {
  speedCamera,
  redLight,

  /// An average speed check over a stretch (trajectcontrole).
  section;

  static CameraKind? from(Object? kind) => switch (kind) {
    'speed_camera' => speedCamera,
    'red_light' => redLight,
    'section_start' => section,
    _ => null,
  };
}

/// A camera on the route, or the start of a section: how far along the route.
typedef RouteCamera = ({CameraKind kind, double along, int? maxspeed});

/// An average speed check on the route: from [start] to [end] along the route.
typedef RouteSection = ({String id, double start, double end, int? maxspeed});

/// What of the enforcement layer lies on one route, in order along it.
class CamerasOnRoute {
  const CamerasOnRoute(this.cameras, this.sections);

  static const empty = CamerasOnRoute([], []);

  /// Speed and red light cameras, and where each section begins.
  final List<RouteCamera> cameras;
  final List<RouteSection> sections;

  /// The first camera ahead of [along], no further than [within].
  ({CameraKind kind, double ahead, int? maxspeed})? next(
    double along,
    double within,
  ) {
    for (final camera in cameras) {
      final ahead = camera.along - along;
      if (ahead < 0) continue;
      if (ahead > within) return null;
      return (kind: camera.kind, ahead: ahead, maxspeed: camera.maxspeed);
    }
    return null;
  }

  /// The section you are in at [along], if any.
  RouteSection? sectionAt(double along) {
    for (final section in sections) {
      if (section.start <= along && along < section.end) return section;
    }
    return null;
  }
}

/// Which cameras from [layer] are on the route of [tracker]: within
/// [maxDistance] of the line and, when the camera has a direction, for your
/// direction of travel (the other carriageway of a motorway is close by too).
/// A section counts when both its start and its end are on the route, in
/// that order.
CamerasOnRoute camerasOnRoute(
  RouteTracker tracker,
  Map<String, dynamic>? layer, {
  double maxDistance = 30,
  double maxAngle = 60,
}) {
  final route = tracker.route.points;
  if (layer == null || route.length < 2) return CamerasOnRoute.empty;
  var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
  for (final p in route) {
    south = min(south, p.latitude);
    north = max(north, p.latitude);
    west = min(west, p.longitude);
    east = max(east, p.longitude);
  }
  const margin = 0.001; // ~100 m
  final cameras = <RouteCamera>[];
  final starts = <String, ({double along, int? maxspeed})>{};
  final ends = <String, double>{};
  for (final feature in (layer['features'] as List? ?? const [])) {
    if (feature is! Map) continue;
    final props = feature['properties'];
    final geometry = feature['geometry'];
    if (props is! Map || geometry is! Map || geometry['type'] != 'Point') {
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
        (heading is num &&
            angleDiff(heading.toDouble(), position.heading) > maxAngle)) {
      continue;
    }
    final maxspeed = (props['maxspeed'] as num?)?.toInt();
    final section = props['section'];
    switch (props['kind']) {
      case 'section_start' when section is String:
        starts[section] = (along: position.along, maxspeed: maxspeed);
      case 'section_end' when section is String:
        ends[section] = position.along;
      case final kind:
        if (CameraKind.from(kind) case final known?) {
          cameras.add((kind: known, along: position.along, maxspeed: maxspeed));
        }
    }
  }
  final sections = <RouteSection>[
    for (final MapEntry(key: id, value: start) in starts.entries)
      if (ends[id] case final end? when end > start.along)
        (id: id, start: start.along, end: end, maxspeed: start.maxspeed),
  ]..sort((a, b) => a.start.compareTo(b.start));
  cameras
    ..addAll([
      for (final s in sections)
        (kind: CameraKind.section, along: s.start, maxspeed: s.maxspeed),
    ])
    ..sort((a, b) => a.along.compareTo(b.along));
  return CamerasOnRoute(cameras, sections);
}
