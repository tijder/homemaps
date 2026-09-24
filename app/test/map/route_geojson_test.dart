import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/map/route_geojson.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../navigation_test.dart' show stroe;

void main() {
  test('routes: one line per route, the chosen one marked', () {
    final route = stroe();
    final json = routesFeatureCollection([route, route], 1);
    final features = json['features'] as List;
    expect(features, hasLength(2));
    expect((features[0] as Map)['properties'], {'chosen': false, 'index': 0});
    expect((features[1] as Map)['properties'], {'chosen': true, 'index': 1});
    final coordinates =
        ((features[0] as Map)['geometry'] as Map)['coordinates'] as List;
    expect(coordinates.first, [
      route.points.first.longitude,
      route.points.first.latitude,
    ]);
  });

  test('a line: nothing without two points', () {
    expect(lineFeatureCollection(null)['features'], isEmpty);
    expect(lineFeatureCollection([const LatLng(52, 5)])['features'], isEmpty);
    expect(
      lineFeatureCollection([
        const LatLng(52, 5),
        const LatLng(52.1, 5),
      ])['features'],
      hasLength(1),
    );
  });

  test('the arrow: the line and a head with the bearing of the last bit', () {
    final json = arrowFeatureCollection([
      const LatLng(52, 5),
      const LatLng(52.1, 5),
      const LatLng(52.1, 5.1),
    ]);
    final features = json['features'] as List;
    expect(features, hasLength(2));
    final head = features[1] as Map;
    expect((head['geometry'] as Map)['type'], 'Point');
    expect((head['properties'] as Map)['bearing'], closeTo(90, 1));
  });
}
