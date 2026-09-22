import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/utils/tijdelijke_snelheden.dart';
import 'package:homemaps/widgets/navigatie_balk.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'navigatie_test.dart' show stroe;

Map<String, dynamic> snelheid(List<LatLng> lijn, int kmu) => {
  'type': 'Feature',
  'properties': {'soort': 'snelheid', 'kmu': kmu},
  'geometry': {
    'type': 'LineString',
    'coordinates': [
      for (final p in lijn) [p.longitude, p.latitude],
    ],
  },
};

Map<String, dynamic> laag(List<Map<String, dynamic>> features) => {
  'type': 'FeatureCollection',
  'features': features,
};

void main() {
  final route = stroe().punten;
  // Een stuk midden in de route, zoals de importer het over de weg legt.
  final werk = route.sublist(20, 41);

  test('een tijdelijke snelheid geldt op het stuk waar hij ligt', () {
    final perStuk = tijdelijkeSnelheden(route, laag([snelheid(werk, 30)]));
    expect(perStuk, hasLength(route.length - 1));
    for (var i = 0; i < perStuk.length; i++) {
      expect(perStuk[i], i >= 20 && i < 40 ? 30 : isNull, reason: 'stuk $i');
    }
  });

  test('de andere kant op, of op een weg ernaast: niet', () {
    // Dezelfde lijn andersom: de rijbaan aan de overkant.
    expect(
      tijdelijkeSnelheden(route, laag([snelheid(werk.reversed.toList(), 30)])),
      everyElement(isNull),
    );
    // 60 m opzij (de weg loopt hier west en noordwest): een parallelweg.
    expect(
      tijdelijkeSnelheden(
        route,
        laag([
          snelheid([
            for (final p in werk) LatLng(p.latitude + 60 / 110574, p.longitude),
          ], 30),
        ]),
      ),
      everyElement(isNull),
    );
  });

  test('twee over elkaar: de laagste; andere soorten tellen niet', () {
    final werkLaag = laag([
      snelheid(werk, 50),
      snelheid(werk.sublist(5, 11), 30),
      {
        'type': 'Feature',
        'properties': {'soort': 'werk', 'kmu': 10},
        'geometry': snelheid(werk, 10)['geometry'],
      },
    ]);
    final perStuk = tijdelijkeSnelheden(route, werkLaag);
    expect(perStuk[22], 50);
    expect(perStuk[27], 30);
    expect(tijdelijkeSnelheden(route, null), everyElement(isNull));
  });

  test('MultiLineString, zoals heen en terug in één feature', () {
    final multi = {
      'type': 'Feature',
      'properties': {'soort': 'snelheid', 'kmu': 30},
      'geometry': {
        'type': 'MultiLineString',
        'coordinates': [
          [
            for (final p in werk.sublist(0, 6)) [p.longitude, p.latitude],
          ],
          [
            for (final p in werk.sublist(5)) [p.longitude, p.latitude],
          ],
        ],
      },
    };
    final perStuk = tijdelijkeSnelheden(route, laag([multi]));
    expect(perStuk.sublist(20, 40), everyElement(30));
  });

  testWidgets('het bord: een werk-pictogram bij een tijdelijke limiet', (
    tester,
  ) async {
    Future<void> bord({required bool tijdelijk}) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SnelheidBord(limiet: 30, snelheid: 12, tijdelijk: tijdelijk),
        ),
      ),
    );
    await bord(tijdelijk: true);
    expect(find.text('30'), findsOneWidget);
    expect(find.byIcon(Icons.construction), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^Tijdelijke maximumsnelheid 30 km/u')),
      findsOneWidget,
    );
    await bord(tijdelijk: false);
    expect(find.byIcon(Icons.construction), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('^Maximumsnelheid 30 km/u')),
      findsOneWidget,
    );
  });
}
