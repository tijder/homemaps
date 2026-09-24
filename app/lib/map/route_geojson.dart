import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/route.dart';
import '../utils/distance.dart';

/// The GeoJSON the map draws: the routes, the driven part and the turn arrow.
/// Pure Dart, so the phone's MapLibre and the car's native MapLibre draw the
/// same thing.

const emptyFeatureCollection = {
  'type': 'FeatureCollection',
  'features': <dynamic>[],
};

List<List<double>> _coordinates(List<LatLng> line) => [
  for (final p in line) [p.longitude, p.latitude],
];

/// The routes, with `chosen` and `index` on each so the style can color the
/// chosen one and a tap knows which one it hit.
Map<String, dynamic> routesFeatureCollection(
  List<RouteOption> routes,
  int chosen,
) => {
  'type': 'FeatureCollection',
  'features': [
    for (final (i, route) in routes.indexed)
      {
        'type': 'Feature',
        'id': i,
        'properties': {'chosen': i == chosen, 'index': i},
        'geometry': {
          'type': 'LineString',
          'coordinates': _coordinates(route.points),
        },
      },
  ],
};

/// One line, or nothing if it is missing or too short.
Map<String, dynamic> lineFeatureCollection(List<LatLng>? line) => {
  'type': 'FeatureCollection',
  'features': [
    if (line != null && line.length > 1)
      {
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {'type': 'LineString', 'coordinates': _coordinates(line)},
      },
  ],
};

/// The turn arrow: the line, and a point at its end with the `bearing` for the
/// arrow head.
Map<String, dynamic> arrowFeatureCollection(List<LatLng>? line) => {
  'type': 'FeatureCollection',
  'features': [
    if (line != null && line.length > 1) ...[
      {
        'type': 'Feature',
        'properties': <String, dynamic>{},
        'geometry': {'type': 'LineString', 'coordinates': _coordinates(line)},
      },
      {
        'type': 'Feature',
        'properties': {
          'bearing': headingBetween(line[line.length - 2], line.last),
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [line.last.longitude, line.last.latitude],
        },
      },
    ],
  ],
};
