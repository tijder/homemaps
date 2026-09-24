import 'dart:math';

import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/route.dart';
import '../providers/location.dart';
import '../utils/distance.dart';

/// Where you are relative to the route, after one fix.
class NavStatus {
  const NavStatus({
    required this.onRoute,
    required this.segment,
    required this.along,
    required this.deviation,
    required this.routeHeading,
    required this.next,
    required this.toNext,
    required this.remainingMeters,
    required this.remainingSeconds,
    required this.offRoute,
    required this.arrived,
  });

  /// The point on the route closest to the fix.
  final LatLng onRoute;

  /// The piece of the shape [onRoute] lies on: between point [segment] and the
  /// next.
  final int segment;

  /// Meters from the start of the route to [onRoute].
  final double along;

  /// Meters between the fix and the route.
  final double deviation;

  /// The route's heading here, in degrees.
  final double routeHeading;

  /// Index in [RouteOption.maneuvers] of the next maneuver.
  final int next;
  final double toNext;
  final double remainingMeters;
  final double remainingSeconds;

  /// Several fixes in a row too far from the route (or the wrong way).
  final bool offRoute;
  final bool arrived;
}

/// Matches fixes to one route. Keeps track of where you were, so a road that
/// comes back right next to itself (a cloverleaf, a hairpin) doesn't make it
/// jump.
class RouteTracker {
  RouteTracker(this.route) : _distanceTo = _cumulative(route.points);

  final RouteOption route;

  /// Meters from the start to each point of the shape.
  final List<double> _distanceTo;

  int? _segment;
  int _tooFar = 0;

  /// The previous fix and how far along the route it was: to know how far along
  /// the route you *can* have got since.
  LatLng? _previousPosition;
  double _previousAlong = 0;

  /// How far a fix may be from the route (plus twice its uncertainty).
  static const maxDeviation = 35.0;

  /// This many fixes in a row too far away before it's "off route".
  static const fixesUntilOffRoute = 3;

  /// Within this many meters of the end you've arrived.
  static const arrivalRadius = 25.0;

  double get length => _distanceTo.isEmpty ? 0 : _distanceTo.last;

  double toManeuver(int index) =>
      _distanceTo[route.maneuvers[index].shapeIndex.clamp(
        0,
        _distanceTo.length - 1,
      )];

  static List<double> _cumulative(List<LatLng> points) {
    final cumulative = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cumulative.add(cumulative.last + meters(points[i - 1], points[i]));
    }
    return cumulative;
  }

  NavStatus track(LocationFix fix) {
    final points = route.points;
    // First only close around the previous position: a bit back (noise) and a
    // way ahead. Only if nothing is near there, the whole route.
    final previous = _segment;
    // How far along the route you can have got: no further than you've travelled
    // since the previous fix, with some slack for noise. That way a road running
    // parallel right next to the route doesn't count as "the route further on"
    // if you haven't driven the turn onto it (Houtbeekweg/Tolnegenweg in Stroe
    // are 40 m apart).
    final previousPosition = _previousPosition;
    final reach = previousPosition == null
        ? double.infinity
        : _previousAlong +
              meters(previousPosition, fix.point) * 1.5 +
              20 +
              min(fix.accuracy, 50);
    var best = previous == null
        ? _find(fix.point, 0, points.length - 2)
        : _find(
            fix.point,
            max(0, previous - 3),
            _segmentAfter(reach),
            maxAlong: reach,
          );
    if (previous != null && best.distance > maxDeviation) {
      final global = _find(fix.point, 0, points.length - 2);
      // Only jump if it clearly fits better elsewhere; otherwise you're simply
      // off the route. A stretch you can't have reached doesn't count either:
      // that's the parallel road from above.
      final globalAlong =
          _distanceTo[global.segment] +
          global.fraction *
              (_distanceTo[global.segment + 1] - _distanceTo[global.segment]);
      if (global.distance < best.distance / 2 &&
          (globalAlong <= reach || _tooFar >= fixesUntilOffRoute)) {
        best = global;
      }
    }
    final segment = best.segment;

    final threshold = maxDeviation + 2 * min(fix.accuracy, 50);
    final heading = headingBetween(points[segment], points[segment + 1]);
    final against =
        fix.heading != null &&
        (fix.speed ?? 0) > 5 &&
        _angleDiff(fix.heading!, heading) > 100;
    if (best.distance > threshold || against) {
      _tooFar++;
    } else {
      _tooFar = 0;
      _segment = segment;
    }
    _segment ??= segment;

    final along =
        _distanceTo[segment] +
        best.fraction * (_distanceTo[segment + 1] - _distanceTo[segment]);
    _previousPosition = fix.point;
    if (_tooFar == 0) _previousAlong = along;
    final maneuvers = route.maneuvers;
    var next = maneuvers.length - 1;
    for (var i = 0; i < maneuvers.length; i++) {
      // A few meters of slack: once you're just through the turn, it's done.
      if (toManeuver(i) > along + 5) {
        next = i;
        break;
      }
    }
    final rest = max(0.0, length - along);
    return NavStatus(
      onRoute: best.point,
      segment: segment,
      along: along,
      deviation: best.distance,
      routeHeading: heading,
      next: next,
      toNext: max(0.0, toManeuver(next) - along),
      remainingMeters: rest,
      remainingSeconds: _remainingTime(along),
      offRoute: _tooFar >= fixesUntilOffRoute,
      arrived: rest < arrivalRadius && best.distance < 50,
    );
  }

  /// Where a single point (an accident) lies on the route: how far along the
  /// route, how far off it, and the route's heading there. Independent of where
  /// you're driving.
  ({double along, double distance, double heading}) locate(LatLng point) {
    final best = _find(point, 0, route.points.length - 2);
    final i = best.segment;
    return (
      along:
          _distanceTo[i] +
          best.fraction * (_distanceTo[i + 1] - _distanceTo[i]),
      distance: best.distance,
      heading: headingBetween(route.points[i], route.points[i + 1]),
    );
  }

  /// How far along the route each of [places] lies, given in order along the
  /// route: each place is only searched for *after* the previous one, so a road
  /// that comes back right next to itself (a cloverleaf) doesn't jump. Null for
  /// a place more than [maxDeviation] from the route.
  List<double?> alongOf(List<LatLng> places) {
    var from = 0;
    return [
      for (final position in places)
        () {
          final best = _find(position, from, route.points.length - 2);
          if (best.distance > maxDeviation) return null;
          from = best.segment;
          final i = best.segment;
          return _distanceTo[i] +
              best.fraction * (_distanceTo[i + 1] - _distanceTo[i]);
        }(),
    ];
  }

  /// What's left of the route, from [status].
  List<LatLng> rest(NavStatus status) => [
    status.onRoute,
    ...route.points.skip(status.segment + 1),
  ];

  /// Each maneuver's time applies to its own stretch; of the stretch you're on
  /// now only what's left counts.
  double _remainingTime(double along) {
    var rest = 0.0;
    for (final m in route.maneuvers) {
      final begin = _distanceTo[m.shapeIndex.clamp(0, _distanceTo.length - 1)];
      final end = _distanceTo[m.endShapeIndex.clamp(0, _distanceTo.length - 1)];
      if (end <= along) continue;
      if (begin >= along || end <= begin) {
        rest += m.seconds;
      } else {
        rest += m.seconds * (end - along) / (end - begin);
      }
    }
    return rest;
  }

  int _segmentAfter(double distance) {
    var i = _segment ?? 0;
    while (i < _distanceTo.length - 2 && _distanceTo[i + 1] < distance) {
      i++;
    }
    return i;
  }

  /// [maxAlong]: don't search further along the route than this (not even
  /// halfway through a long stretch).
  ({int segment, double fraction, double distance, LatLng point}) _find(
    LatLng p,
    int from,
    int to, {
    double maxAlong = double.infinity,
  }) {
    final points = route.points;
    var best = (
      segment: from,
      fraction: 0.0,
      distance: double.infinity,
      point: p,
    );
    // A flat projection around the fix: over a few kilometers that's accurate
    // to the centimeter, and much faster than spherical geometry per segment.
    final cosLat = cos(p.latitude * pi / 180);
    ({double x, double y}) project(LatLng q) => (
      x: (q.longitude - p.longitude) * cosLat * 111320,
      y: (q.latitude - p.latitude) * 110574,
    );
    for (var i = from; i <= to && i < points.length - 1; i++) {
      final a = project(points[i]), b = project(points[i + 1]);
      final dx = b.x - a.x, dy = b.y - a.y;
      final squared = dx * dx + dy * dy;
      final length = _distanceTo[i + 1] - _distanceTo[i];
      final tMax = length <= 0
          ? 1.0
          : ((maxAlong - _distanceTo[i]) / length).clamp(0.0, 1.0);
      final t = squared == 0
          ? 0.0
          : ((-a.x * dx - a.y * dy) / squared).clamp(0.0, tMax);
      final x = a.x + t * dx, y = a.y + t * dy;
      final distance = sqrt(x * x + y * y);
      if (distance < best.distance) {
        final a0 = points[i], b0 = points[i + 1];
        best = (
          segment: i,
          fraction: t,
          distance: distance,
          point: LatLng(
            a0.latitude + t * (b0.latitude - a0.latitude),
            a0.longitude + t * (b0.longitude - a0.longitude),
          ),
        );
      }
    }
    return best;
  }
}

double angleDiff(double a, double b) => _angleDiff(a, b);

double _angleDiff(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}
