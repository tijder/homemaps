import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/models/place.dart';
import 'package:homemaps/navigation/navigation_provider.dart';
import 'package:homemaps/navigation/route_geometry.dart';
import 'package:homemaps/navigation/route_tracker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../navigation_test.dart' show along, east, fix, stroe;

void main() {
  final route = stroe();
  final destinations = [Place(label: 'x', point: route.points.last)];

  NavigationState navAt(LatLng point) {
    final tracker = RouteTracker(route);
    final status = tracker.track(fix(point));
    return NavigationState(
      route: route,
      destinations: destinations,
      status: status,
      fix: fix(point),
    );
  }

  test('on the route the dot snaps to the road, with the road heading', () {
    final point = along(route.points, 20)[10];
    final nav = navAt(east(point, 5));
    final snapped = snapToRoute(nav, nav.fix)!;
    expect(snapped.point, nav.status!.onRoute);
    expect(snapped.heading, nav.status!.routeHeading);
    // Far off: the fix itself.
    final away = navAt(east(point, 100));
    expect(snapToRoute(away, away.fix), same(away.fix));
    expect(snapToRoute(null, away.fix), same(away.fix));
  });

  test('the driven line ends at the point on the route', () {
    final nav = navAt(along(route.points, 20)[10]);
    final line = drivenLine(nav)!;
    expect(line.last, nav.status!.onRoute);
    expect(line.length, nav.status!.segment + 2);
    expect(drivenLine(null), isNull);
  });

  test('the arrow: once per maneuver, and only when it is close', () {
    final cache = TurnArrowCache();
    final points = along(route.points, 20);
    final first = cache.arrowFor(navAt(points[1]));
    final again = cache.arrowFor(navAt(points[2]));
    if (first != null) expect(again, same(first));
    expect(cache.arrowFor(null), isNull);
  });

  test('the zoom follows the speed', () {
    expect(followZoom(0), 17);
    expect(followZoom(13), closeTo(16.2, 0.01));
    expect(followZoom(40), 14.5);
  });
}
