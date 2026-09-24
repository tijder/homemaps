import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/utils/night_style.dart';

void main() {
  test('parsing colours: hex, rgb(a), hsl(a); nothing else', () {
    expect(parseColor('#fff'), (h: 0.0, s: 0.0, l: 1.0, a: 1.0));
    final orange = parseColor('#ffcc88')!; // #fc8, the motorway
    expect(orange.h, closeTo(34.3, 0.1));
    expect(orange.l, closeTo(0.767, 0.01));
    expect(parseColor('rgba(255,255,255,0.7)')!.a, 0.7);
    expect(parseColor('hsla(30, 19%, 90%, 0.4)'), (
      h: 30.0,
      s: 0.19,
      l: 0.9,
      a: 0.4,
    ));
    expect(parseColor('hsl(210, 67%, 85%)')!.a, 1);
    expect(parseColor('class'), isNull);
    expect(parseColor('red'), isNull);
  });

  Map<String, dynamic> style(List<Map<String, dynamic>> layers) => {
    'version': 8,
    'name': 'OSM Bright',
    'sources': {'openmaptiles': {}},
    'layers': layers,
  };

  double l(Object? color) => parseColor(color! as String)!.l;

  test('areas dark, roads lighter than the background, text light', () {
    final night = nightStyle(
      style([
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
    final layers = {
      for (final layer in night['layers'] as List)
        (layer as Map)['id']: layer['paint'] as Map,
    };
    final land = l(layers['background']!['background-color']);
    final motorway = l(layers['highway-motorway']!['line-color']);
    final casing = l(layers['highway-motorway-casing']!['line-color']);
    expect(land, lessThan(0.1));
    expect(motorway, greaterThan(land + 0.2));
    expect(casing, allOf(greaterThan(land), lessThan(motorway)));
    // The motorway stays orange; the pale yellow of a provincial road does
    // not suddenly become bright yellow.
    final orange = parseColor(
      layers['highway-motorway']!['line-color'] as String,
    )!;
    expect(orange.h, closeTo(35, 1));
    expect(orange.s, greaterThan(0.3));
    final yellow = parseColor(
      layers['highway-primary']!['line-color'] as String,
    )!;
    expect(yellow.s, lessThan(orange.s));
    // Text light with a dark halo; the halo is also added where there was
    // none.
    expect(l(layers['place-city']!['text-color']), greaterThan(0.8));
    expect(l(layers['place-city']!['text-halo-color']), lessThan(0.1));
    expect(
      parseColor(layers['place-city']!['text-halo-color'] as String)!.a,
      0.8,
    );
    expect(l(layers['highway-name-minor']!['text-halo-color']), lessThan(0.1));
    expect(layers['highway-name-minor']!['text-halo-width'], 1.2);
    expect(night['name'], 'OSM Bright (night)');
    expect(night['sources'], {'openmaptiles': {}});
  });

  test(
    'text on a shield stays black without halo, text next to an icon does not',
    () {
      final night = nightStyle(
        style([
          {
            'id': 'highway-shield',
            'type': 'symbol',
            'layout': {
              'icon-image': 'road_{ref_length}',
              'text-field': '{ref}',
            },
            'paint': <String, dynamic>{},
          },
          {
            'id': 'highway-shield-us-other',
            'type': 'symbol',
            'layout': {
              'icon-image': '{network}_{ref_length}',
              'text-field': '{ref}',
            },
            'paint': {'text-color': 'rgba(0, 0, 0, 1)'},
          },
          {
            'id': 'poi-level-1',
            'type': 'symbol',
            'layout': {
              'icon-image': '{class}_11',
              'text-field': '{name:latin}',
              'text-offset': [0, 0.6],
            },
            'paint': {'text-color': '#666', 'text-halo-color': '#ffffff'},
          },
        ]),
      );
      final layers = [
        for (final layer in night['layers'] as List) layer['paint'],
      ];
      expect(layers[0], isEmpty);
      expect(layers[1], {'text-color': 'rgba(0, 0, 0, 1)'});
      expect(l(layers[2]['text-color']), greaterThan(0.6));
      expect(l(layers[2]['text-halo-color']), lessThan(0.1));
    },
  );

  test('colours in stops and expressions; the rest stays', () {
    final night = nightStyle(
      style([
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
        {'id': 'no-paint', 'type': 'line'},
      ]),
    );
    final layers = night['layers'] as List;
    final stops = (layers[0]['paint']['fill-color']['stops'] as List);
    expect(l(stops[0][1]), lessThan(0.15));
    expect(stops[0][0], 15.5);
    expect(layers[0]['paint']['fill-opacity'], 0.5);
    final match = layers[1]['paint']['fill-color'] as List;
    expect(match.sublist(0, 3), [
      'match',
      ['get', 'class'],
      'park',
    ]);
    expect(l(match[3]), lessThan(0.15));
    expect(layers[1]['layout'], {'visibility': 'visible'});
    expect(layers[2], {'id': 'no-paint', 'type': 'line'});
  });
}
