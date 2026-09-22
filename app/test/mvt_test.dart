import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/utils/mvt.dart';

void main() {
  test('POI\'s uit een echte tegel (Stroe/Barneveld, z14)', () {
    final punten = puntenUitTegel(
      File('test/fixtures/tegel_14_8446_5405.pbf').readAsBytesSync(),
      laag: 'poi',
      z: 14,
      x: 8446,
      y: 5405,
    );
    // Dezelfde tegel gaf met mapbox-vector-tile (Python) 22 POI's.
    expect(punten, hasLength(22));
    final esso = punten.singleWhere((p) => p.eigenschappen['class'] == 'fuel');
    expect(esso.eigenschappen['name'], 'Esso De Stroet');
    expect(esso.eigenschappen['rank'], 1);
    // Tegel 14/8446/5405: 52.0795-52.0930 N, 5.5811-5.6030 O, plus de rand die
    // een vectortegel meeneemt (een kwart tegel). De Esso staat in de tegel op
    // (3571, 1773) van 4096.
    for (final p in punten) {
      expect(p.punt.latitude, inInclusiveRange(52.0761, 52.0964));
      expect(p.punt.longitude, inInclusiveRange(5.5755, 5.6086));
    }
    expect(esso.punt.latitude, closeTo(52.0872, 0.0003));
    expect(esso.punt.longitude, closeTo(5.6002, 0.0003));
  });
}
