import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/navigation/navigation_provider.dart';
import 'package:homemaps/utils/temporary_speed_limits.dart';
import 'package:homemaps/widgets/navigation_bar.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'navigation_test.dart' show stroe;

Map<String, dynamic> speed(List<LatLng> line, int kmh) => {
  'type': 'Feature',
  'properties': {'kind': 'speed_limit', 'kph': kmh},
  'geometry': {
    'type': 'LineString',
    'coordinates': [
      for (final p in line) [p.longitude, p.latitude],
    ],
  },
};

Map<String, dynamic> layer(List<Map<String, dynamic>> features) => {
  'type': 'FeatureCollection',
  'features': features,
};

void main() {
  final route = stroe().points;
  // A stretch in the middle of the route, as the importer lays it over the road.
  final roadworks = route.sublist(20, 41);

  test('a temporary speed limit applies to the stretch where it lies', () {
    final perStretch = temporarySpeedLimits(
      route,
      layer([speed(roadworks, 30)]),
    );
    expect(perStretch, hasLength(route.length - 1));
    for (var i = 0; i < perStretch.length; i++) {
      expect(
        perStretch[i],
        i >= 20 && i < 40 ? 30 : isNull,
        reason: 'stretch $i',
      );
    }
  });

  test('the other direction, or on a road next to it: no', () {
    // The same line reversed: the carriageway on the opposite side.
    expect(
      temporarySpeedLimits(
        route,
        layer([speed(roadworks.reversed.toList(), 30)]),
      ),
      everyElement(isNull),
    );
    // 60 m to the side (the road runs west and northwest here): a parallel road.
    expect(
      temporarySpeedLimits(
        route,
        layer([
          speed([
            for (final p in roadworks)
              LatLng(p.latitude + 60 / 110574, p.longitude),
          ], 30),
        ]),
      ),
      everyElement(isNull),
    );
  });

  test('two overlapping: the lowest; other kinds do not count', () {
    final worksLayer = layer([
      speed(roadworks, 50),
      speed(roadworks.sublist(5, 11), 30),
      {
        'type': 'Feature',
        'properties': {'kind': 'roadworks', 'kph': 10},
        'geometry': speed(roadworks, 10)['geometry'],
      },
    ]);
    final perStretch = temporarySpeedLimits(route, worksLayer);
    expect(perStretch[22], 50);
    expect(perStretch[27], 30);
    expect(temporarySpeedLimits(route, null), everyElement(isNull));
  });

  test('MultiLineString, like both directions in one feature', () {
    final multi = {
      'type': 'Feature',
      'properties': {'kind': 'speed_limit', 'kph': 30},
      'geometry': {
        'type': 'MultiLineString',
        'coordinates': [
          [
            for (final p in roadworks.sublist(0, 6)) [p.longitude, p.latitude],
          ],
          [
            for (final p in roadworks.sublist(5)) [p.longitude, p.latitude],
          ],
        ],
      },
    };
    final perStretch = temporarySpeedLimits(route, layer([multi]));
    expect(perStretch.sublist(20, 40), everyElement(30));
  });

  testWidgets('the sign: a roadworks icon for a temporary limit', (
    tester,
  ) async {
    Future<void> sign({required bool temporary}) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SpeedLimitSign(
            limit: 30,
            speed: 12,
            source: temporary ? LimitSource.roadworks : LimitSource.osm,
          ),
        ),
      ),
    );
    await sign(temporary: true);
    expect(find.text('30'), findsOneWidget);
    expect(find.byIcon(Icons.construction), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('^Tijdelijke maximumsnelheid 30 km/u')),
      findsOneWidget,
    );
    await sign(temporary: false);
    expect(find.byIcon(Icons.construction), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('^Maximumsnelheid 30 km/u')),
      findsOneWidget,
    );
  });
}
