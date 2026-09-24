import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/utils/mvt.dart';

void main() {
  test('POIs from a real tile (Stroe/Barneveld, z14)', () {
    final points = pointsFromTile(
      File('test/fixtures/tile_14_8446_5405.pbf').readAsBytesSync(),
      layer: 'poi',
      z: 14,
      x: 8446,
      y: 5405,
    );
    // The same tile gave 22 POIs with mapbox-vector-tile (Python).
    expect(points, hasLength(22));
    final esso = points.singleWhere((p) => p.properties['class'] == 'fuel');
    expect(esso.properties['name'], 'Esso De Stroet');
    expect(esso.properties['rank'], 1);
    // Tile 14/8446/5405: 52.0795-52.0930 N, 5.5811-5.6030 E, plus the buffer a
    // vector tile includes (a quarter tile). The Esso is in the tile at
    // (3571, 1773) of 4096.
    for (final p in points) {
      expect(p.point.latitude, inInclusiveRange(52.0761, 52.0964));
      expect(p.point.longitude, inInclusiveRange(5.5755, 5.6086));
    }
    expect(esso.point.latitude, closeTo(52.0872, 0.0003));
    expect(esso.point.longitude, closeTo(5.6002, 0.0003));
  });
}
