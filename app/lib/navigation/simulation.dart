import 'dart:async';
import 'dart:math';

import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/route.dart';
import '../providers/location.dart';
import '../utils/distance.dart';

/// A fake GPS that drives the route, to test navigation without driving. On the
/// web, turn it on with `?simulate=52.186,5.7035` (the start point), optionally
/// with `&speed=14` (m/s) and `&miss=3` (go straight on at maneuver 3, so the
/// route has to be recalculated).
class SimulationSource implements LocationFixSource {
  SimulationSource(this._position, {this.speed = 14, this.missAt});

  LatLng _position;
  final double speed;
  final int? missAt;

  List<LatLng>? _path;
  List<double> _distanceTo = const [];
  double _travelled = 0;
  double _heading = 0;
  double? _missAtMeter;
  bool _missed = false;

  /// Still (start or arrived), along the route, or straight on after a missed
  /// turn.
  var _mode = _Mode.still;

  /// Drive this route from now on (navigation calls this for every new or
  /// recalculated route).
  void drive(RouteOption route) {
    _path = route.points;
    _distanceTo = [0];
    for (var i = 1; i < route.points.length; i++) {
      _distanceTo.add(
        _distanceTo.last + meters(route.points[i - 1], route.points[i]),
      );
    }
    _travelled = 0;
    _mode = _Mode.route;
    final index = missAt;
    _missAtMeter = !_missed && index != null && index < route.maneuvers.length
        ? _distanceTo[route.maneuvers[index].shapeIndex]
        : null;
  }

  @override
  Future<PermissionAnswer> check() async => PermissionAnswer.yes;

  @override
  Future<PermissionAnswer> ask() async => PermissionAnswer.yes;

  @override
  Stream<LocationFix> follow({
    required bool accurate,
    ({String title, String text})? notification,
  }) {
    late final StreamController<LocationFix> out;
    Timer? tick;
    out = StreamController<LocationFix>(
      onListen: () {
        out.add(_fix(0));
        tick = Timer.periodic(
          const Duration(seconds: 1),
          (_) => out.add(_fix(speed)),
        );
      },
      onCancel: () => tick?.cancel(),
    );
    return out.stream;
  }

  LocationFix _fix(double step) {
    switch (_mode) {
      case _Mode.still:
        break;
      case _Mode.route:
        _alongRoute(step);
      case _Mode.straight:
        final r = _heading * pi / 180;
        _position = LatLng(
          _position.latitude + step * cos(r) / 110574,
          _position.longitude +
              step * sin(r) / (111320 * cos(_position.latitude * pi / 180)),
        );
    }
    final driving = _mode != _Mode.still;
    return LocationFix(
      point: _position,
      time: DateTime.now(),
      accuracy: 5,
      heading: driving ? _heading : null,
      speed: driving ? speed : 0,
    );
  }

  void _alongRoute(double step) {
    final path = _path!;
    _travelled += step;
    final miss = _missAtMeter;
    if (miss != null && _travelled >= miss) {
      // Miss the turn: straight on, off the route, until there's a new one.
      _missed = true;
      _mode = _Mode.straight;
      return;
    }
    if (_travelled >= _distanceTo.last) {
      _position = path.last;
      _mode = _Mode.still;
      return;
    }
    var i = 0;
    while (_distanceTo[i + 1] < _travelled) {
      i++;
    }
    final t =
        (_travelled - _distanceTo[i]) /
        max(_distanceTo[i + 1] - _distanceTo[i], 0.001);
    final a = path[i], b = path[i + 1];
    _position = LatLng(
      a.latitude + t * (b.latitude - a.latitude),
      a.longitude + t * (b.longitude - a.longitude),
    );
    if (meters(a, b) > 0.5) _heading = _bearing(a, b);
  }

  static double _bearing(LatLng a, LatLng b) {
    final f1 = a.latitude * pi / 180, f2 = b.latitude * pi / 180;
    final dl = (b.longitude - a.longitude) * pi / 180;
    return (atan2(
                  sin(dl) * cos(f2),
                  cos(f1) * sin(f2) - sin(f1) * cos(f2) * cos(dl),
                ) *
                180 /
                pi +
            360) %
        360;
  }

  /// From the web app's URL, or null if it contains no simulation.
  static SimulationSource? fromUrl(Uri url) {
    final start = url.queryParameters['simulate']?.split(',');
    if (start == null || start.length != 2) return null;
    final lat = double.tryParse(start[0]), lon = double.tryParse(start[1]);
    if (lat == null || lon == null) return null;
    return SimulationSource(
      LatLng(lat, lon),
      speed: double.tryParse(url.queryParameters['speed'] ?? '') ?? 14,
      missAt: int.tryParse(url.queryParameters['miss'] ?? ''),
    );
  }
}

enum _Mode { still, route, straight }
