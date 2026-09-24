import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/utils/planned_closures.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'navigation_test.dart' show along, east, stroe;

void main() {
  final route = stroe();
  final departure = DateTime.utc(2026, 9, 23, 21, 0);
  final stretch = along(route.points, 20).sublist(40, 50); // 200 m of the route

  Map<String, dynamic> layer(List<LatLng> line, String from, String? until) => {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': {
          'kind': 'planned',
          'windows': [
            [from, until],
          ],
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final p in line) [p.longitude, p.latitude],
          ],
        },
      },
    ],
  };

  test('on the route and in the window: found', () {
    final found = closuresOnRoute(
      route,
      layer(stretch, '2026-09-23T20:00:00Z', '2026-09-24T04:00:00Z'),
      departure,
    );
    expect(found, hasLength(1));
    expect(found.single.from, DateTime.utc(2026, 9, 23, 20));
  });

  test('outside the window, or a road next to it: nothing', () {
    expect(
      closuresOnRoute(
        route,
        layer(stretch, '2026-09-25T20:00:00Z', '2026-09-26T04:00:00Z'),
        departure,
      ),
      isEmpty,
    );
    expect(
      closuresOnRoute(
        route,
        layer(
          [for (final p in stretch) east(p, 100)],
          '2026-09-23T20:00:00Z',
          null,
        ),
        departure,
      ),
      isEmpty,
    );
  });

  test('only starts during the trip (within the hour of slack): found', () {
    // The trip takes ~12 min; the closure starts 40 min after departure.
    expect(
      closuresOnRoute(
        route,
        layer(stretch, '2026-09-23T21:40:00Z', null),
        departure,
      ),
      hasLength(1),
    );
  });
}
