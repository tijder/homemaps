import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/route.dart';
import '../utils/distance.dart';

/// These maneuvers get an arrow on the map: turns, on- and off-ramps, keeping
/// left or right, merging and roundabouts. Not straight on, start, destination
/// or a ferry.
bool hasTurnArrow(Maneuver m) =>
    (m.type >= 9 && m.type <= 21) ||
    (m.type >= 23 && m.type <= 27) ||
    m.type == 37 ||
    m.type == 38;

/// The bit of route around maneuver [index] for the arrow on the map, as in
/// Google and Apple Maps: [before] meters before to [after] meters after. At a
/// roundabout (26) it continues past the exit (27). Null if this maneuver gets
/// no arrow.
List<LatLng>? turnArrow(
  RouteOption route,
  int index, {
  double before = 40,
  double after = 30,
}) {
  final m = route.maneuvers;
  if (index <= 0 || index >= m.length || !hasTurnArrow(m[index])) {
    return null;
  }
  final points = route.points;
  if (points.length < 2) return null;
  final cumulative = <double>[0];
  for (var i = 1; i < points.length; i++) {
    cumulative.add(cumulative.last + meters(points[i - 1], points[i]));
  }
  double along(int shapeIndex) =>
      cumulative[shapeIndex.clamp(0, cumulative.length - 1)];

  var end = m[index];
  if (end.type == 26) {
    final exit = m.indexWhere((x) => x.type == 27, index + 1);
    if (exit > 0) end = m[exit];
  }
  return stretchAlong(
    points,
    cumulative,
    along(m[index].shapeIndex) - before,
    along(end.shapeIndex) + after,
  );
}

/// The part of [points] between [from] and [to] meters along the line, with the
/// ends exactly at that distance. [cumulative] is the distance to each point.
List<LatLng> stretchAlong(
  List<LatLng> points,
  List<double> cumulative,
  double from,
  double to,
) {
  from = from.clamp(0, cumulative.last);
  to = to.clamp(from, cumulative.last);
  LatLng pointAt(double distance) {
    var i = 1;
    while (i < cumulative.length - 1 && cumulative[i] < distance) {
      i++;
    }
    final stretch = cumulative[i] - cumulative[i - 1];
    final t = stretch == 0 ? 0.0 : (distance - cumulative[i - 1]) / stretch;
    final a = points[i - 1], b = points[i];
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  return [
    pointAt(from),
    for (var i = 0; i < points.length; i++)
      if (cumulative[i] > from && cumulative[i] < to) points[i],
    pointAt(to),
  ];
}
