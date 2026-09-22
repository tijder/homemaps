import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/utils/geplande_afsluitingen.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'navigatie_test.dart' show langs, oost, stroe;

void main() {
  final route = stroe();
  final vertrek = DateTime.utc(2026, 9, 23, 21, 0);
  final stuk = langs(route.punten, 20).sublist(40, 50); // 200 m van de route

  Map<String, dynamic> laag(List<LatLng> lijn, String van, String? tot) => {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': {
          'soort': 'gepland',
          'vensters': [
            [van, tot],
          ],
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final p in lijn) [p.longitude, p.latitude],
          ],
        },
      },
    ],
  };

  test('op de route en in het venster: gevonden', () {
    final gevonden = afsluitingenOpRoute(
      route,
      laag(stuk, '2026-09-23T20:00:00Z', '2026-09-24T04:00:00Z'),
      vertrek,
    );
    expect(gevonden, hasLength(1));
    expect(gevonden.single.van, DateTime.utc(2026, 9, 23, 20));
  });

  test('buiten het venster, of een weg ernaast: niets', () {
    expect(
      afsluitingenOpRoute(
        route,
        laag(stuk, '2026-09-25T20:00:00Z', '2026-09-26T04:00:00Z'),
        vertrek,
      ),
      isEmpty,
    );
    expect(
      afsluitingenOpRoute(
        route,
        laag(
          [for (final p in stuk) oost(p, 100)],
          '2026-09-23T20:00:00Z',
          null,
        ),
        vertrek,
      ),
      isEmpty,
    );
  });

  test('begint pas tijdens de rit (binnen het uur speling): gevonden', () {
    // De rit duurt ~12 min; de afsluiting begint 40 min na vertrek.
    expect(
      afsluitingenOpRoute(
        route,
        laag(stuk, '2026-09-23T21:40:00Z', null),
        vertrek,
      ),
      hasLength(1),
    );
  });
}
