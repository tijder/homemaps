import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/route.dart';
import '../providers/location.dart';
import 'navigation_provider.dart';
import 'turn_arrow.dart';

/// What the map shows during navigation, from the navigation state. Pure
/// Dart, shared by the phone screen and the car screens.

/// During navigation the dot sits on the road as long as you drive on the
/// route, as you're used to from a navigation system. Off the route (or
/// without navigation) it is the fix itself.
LocationFix? snapToRoute(NavigationState? nav, LocationFix? fix) {
  final status = nav?.status;
  if (nav == null || status == null || fix == null || status.deviation >= 30) {
    return fix;
  }
  return LocationFix(
    point: status.onRoute,
    time: fix.time,
    accuracy: fix.accuracy,
    heading: status.routeHeading,
    speed: fix.speed,
  );
}

/// The part of the route already behind you, up to the point on the route.
List<LatLng>? drivenLine(NavigationState? nav) {
  final status = nav?.status;
  if (nav == null || status == null) return null;
  return [...nav.route.points.take(status.segment + 1), status.onRoute];
}

/// The arrow at the next turn, if it's close. Computed once per maneuver; the
/// same list comes back as long as the route and the next maneuver are the
/// same, so the map doesn't redraw it on every fix.
class TurnArrowCache {
  /// The arrow appears when the next maneuver is within this many meters.
  static const within = 1000.0;

  ({RouteOption route, int index, List<LatLng>? line})? _arrow;

  List<LatLng>? arrowFor(NavigationState? nav) {
    final status = nav?.status;
    if (nav == null ||
        status == null ||
        nav.arrived ||
        nav.recalculating ||
        status.toNext > within) {
      return null;
    }
    final old = _arrow;
    if (old != null &&
        identical(old.route, nav.route) &&
        old.index == status.next) {
      return old.line;
    }
    final line = turnArrow(nav.route, status.next);
    _arrow = (route: nav.route, index: status.next, line: line);
    return line;
  }
}

/// The zoom while following: slow means close by; on the motorway look
/// further ahead.
double followZoom(double speedMs) => (17.5 - speedMs * 0.1).clamp(14.5, 17.0);

/// The tilt while following.
const followTilt = 50.0;

/// The car's screen is low and wide and further from your eyes than the
/// phone: one zoom level further out, so you see as far ahead.
const carZoomOffset = -1.0;
