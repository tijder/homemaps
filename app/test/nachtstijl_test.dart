import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/utils/nachtstijl.dart';

void main() {
  test('kleuren lezen: hex, rgb(a), hsl(a); de rest niet', () {
    expect(leesKleur('#fff'), (h: 0.0, s: 0.0, l: 1.0, a: 1.0));
    final oranje = leesKleur('#ffcc88')!; // #fc8, de snelweg
    expect(oranje.h, closeTo(34.3, 0.1));
    expect(oranje.l, closeTo(0.767, 0.01));
    expect(leesKleur('rgba(255,255,255,0.7)')!.a, 0.7);
    expect(leesKleur('hsla(30, 19%, 90%, 0.4)'), (
      h: 30.0,
      s: 0.19,
      l: 0.9,
      a: 0.4,
    ));
    expect(leesKleur('hsl(210, 67%, 85%)')!.a, 1);
    expect(leesKleur('class'), isNull);
    expect(leesKleur('red'), isNull);
  });

  Map<String, dynamic> stijl(List<Map<String, dynamic>> lagen) => {
    'version': 8,
    'name': 'OSM Bright',
    'sources': {'openmaptiles': {}},
    'layers': lagen,
  };

  double l(Object? kleur) => leesKleur(kleur! as String)!.l;

  test('vlakken donker, wegen lichter dan de ondergrond, tekst licht', () {
    final nacht = nachtstijl(
      stijl([
        {
          'id': 'background',
          'type': 'background',
          'paint': {'background-color': '#f8f4f0'},
        },
        {
          'id': 'highway-motorway-casing',
          'type': 'line',
          'paint': {'line-color': '#e9ac77'},
        },
        {
          'id': 'highway-motorway',
          'type': 'line',
          'paint': {'line-color': '#fc8'},
        },
        {
          'id': 'highway-primary',
          'type': 'line',
          'paint': {'line-color': '#fea'},
        },
        {
          'id': 'place-city',
          'type': 'symbol',
          'paint': {
            'text-color': '#333',
            'text-halo-color': 'rgba(255,255,255,0.8)',
          },
        },
        {
          'id': 'highway-name-minor',
          'type': 'symbol',
          'paint': {'text-color': '#765'},
        },
      ]),
    );
    final lagen = {
      for (final laag in nacht['layers'] as List)
        (laag as Map)['id']: laag['paint'] as Map,
    };
    final land = l(lagen['background']!['background-color']);
    final snelweg = l(lagen['highway-motorway']!['line-color']);
    final rand = l(lagen['highway-motorway-casing']!['line-color']);
    expect(land, lessThan(0.1));
    expect(snelweg, greaterThan(land + 0.2));
    expect(rand, allOf(greaterThan(land), lessThan(snelweg)));
    // De snelweg blijft oranje; het bleekgeel van een provinciale weg wordt
    // niet ineens knalgeel.
    final oranje = leesKleur(
      lagen['highway-motorway']!['line-color'] as String,
    )!;
    expect(oranje.h, closeTo(35, 1));
    expect(oranje.s, greaterThan(0.3));
    final geel = leesKleur(lagen['highway-primary']!['line-color'] as String)!;
    expect(geel.s, lessThan(oranje.s));
    // Tekst licht met een donkere rand; die rand komt er ook waar hij er niet
    // was.
    expect(l(lagen['place-city']!['text-color']), greaterThan(0.8));
    expect(l(lagen['place-city']!['text-halo-color']), lessThan(0.1));
    expect(
      leesKleur(lagen['place-city']!['text-halo-color'] as String)!.a,
      0.8,
    );
    expect(l(lagen['highway-name-minor']!['text-halo-color']), lessThan(0.1));
    expect(lagen['highway-name-minor']!['text-halo-width'], 1.2);
    expect(nacht['name'], 'OSM Bright (nacht)');
    expect(nacht['sources'], {'openmaptiles': {}});
  });

  test('kleuren in stops en expressies; de rest blijft', () {
    final nacht = nachtstijl(
      stijl([
        {
          'id': 'building',
          'type': 'fill',
          'paint': {
            'fill-color': {
              'base': 1,
              'stops': [
                [15.5, '#f2eae2'],
                [16, '#dfdbd7'],
              ],
            },
            'fill-opacity': 0.5,
          },
        },
        {
          'id': 'landuse',
          'type': 'fill',
          'layout': {'visibility': 'visible'},
          'paint': {
            'fill-color': [
              'match',
              ['get', 'class'],
              'park',
              '#d8e8c8',
              '#fff',
            ],
          },
        },
        {'id': 'zonder-paint', 'type': 'line'},
      ]),
    );
    final lagen = nacht['layers'] as List;
    final stops = (lagen[0]['paint']['fill-color']['stops'] as List);
    expect(l(stops[0][1]), lessThan(0.15));
    expect(stops[0][0], 15.5);
    expect(lagen[0]['paint']['fill-opacity'], 0.5);
    final match = lagen[1]['paint']['fill-color'] as List;
    expect(match.sublist(0, 3), [
      'match',
      ['get', 'class'],
      'park',
    ]);
    expect(l(match[3]), lessThan(0.15));
    expect(lagen[1]['layout'], {'visibility': 'visible'});
    expect(lagen[2], {'id': 'zonder-paint', 'type': 'line'});
  });
}
