import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/models/route.dart';
import 'package:homemaps/models/units.dart';
import 'package:homemaps/navigation/navigation_provider.dart';
import 'package:homemaps/utils/formatting.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final nl = lookupAppLocalizations(const Locale('nl'));

  setUpAll(initializeDateFormatting);

  test('a duration in the language of the app', () {
    expect(duration(12 * 60, en), '12 min');
    expect(duration(65 * 60, en), '1 h 05 min');
    expect(duration(65 * 60, nl), '1 u 05');
    // Rounded to the minute before it is split: 59.6 min is an hour.
    expect(duration(59.6 * 60, nl), '1 u 00');
  });

  spokenDistances();

  group('in miles', () {
    setUp(() => displayUnits = Units.imperial);
    tearDown(() => displayUnits = Units.metric);

    test('distances in feet and miles', () {
      expect(distance(20, 'en'), '70 ft');
      expect(distance(120, 'en'), '400 ft');
      expect(distance(800, 'en'), '0.5 mi');
      expect(distance(4000, 'en'), '2.5 mi');
      expect(distance(40000, 'en'), '25 mi');
    });

    test('speeds: your own as it is, a limit as on a sign', () {
      expect(speedIn(27.78), 62);
      expect(limitIn(100), 60);
      expect(limitIn(130), 80);
      expect(limitIn(50), 30);
      expect(limitIn(30), 20);
      expect(speedUnit(en), 'mph');
    });

    test('the voice speaks feet and miles', () {
      final texts = NavTexts.of(en, 'en-US', 'x');
      expect(texts.withDistance(150, 'Turn left.'), contains('500 feet'));
      expect(texts.withDistance(1609, 'Turn left.'), contains('1 mile,'));
      expect(texts.withDistance(4000, 'Turn left.'), contains('2.5 miles'));
    });

    test('a route in miles has the same length in meters', () {
      final trip =
          (jsonDecode(
                File('test/fixtures/valhalla_stroe.json').readAsStringSync(),
              ) as Map<String, dynamic>)['trip']
              as Map<String, dynamic>;
      final metric = RouteOption.fromValhalla(trip, elevationInterval: 30);
      // What Valhalla answers to `units: miles`: the same lengths in miles.
      Object? inMiles(Object? value) => switch (value) {
        final Map<dynamic, dynamic> map => {
          for (final MapEntry(:key, :value) in map.entries)
            key: key == 'length' ? (value as num) / 1.609344 : inMiles(value),
        },
        final List<dynamic> list => [for (final item in list) inMiles(item)],
        _ => value,
      };
      final miles = RouteOption.fromValhalla({
        ...jsonDecode(jsonEncode(inMiles(trip))) as Map<String, dynamic>,
        'units': 'miles',
      }, elevationInterval: 30);
      expect(miles.meters, closeTo(metric.meters, 1));
      expect(
        miles.maneuvers.first.meters,
        closeTo(metric.maneuvers.first.meters, 1),
      );
    });
  });

  test('metric by default', () {
    expect(distance(650, 'en'), '650 m');
    expect(distance(2600, 'nl'), '2,6 km');
    expect(speedIn(27.78), 100);
    expect(limitIn(100), 100);
    expect(speedUnit(en), 'km/h');
  });

  test('a time on another day says which day', () {
    final now = DateTime(2026, 11, 19, 22, 0);
    expect(timeOfDay(DateTime(2026, 11, 19, 23, 30), 'en', now: now), '23:30');
    expect(
      timeOfDay(DateTime(2026, 11, 20, 8, 15), 'en', now: now),
      'Fri 08:15',
    );
    expect(
      timeOfDay(DateTime(2026, 11, 20, 8, 15), 'nl', now: now),
      'vr 08:15',
    );
  });
}

// Spoken distances: see NavTexts.
void spokenDistances() {
  final en = NavTexts.of(
    lookupAppLocalizations(const Locale('en')),
    'en-US',
    'x',
  );
  final nl = NavTexts.of(
    lookupAppLocalizations(const Locale('nl')),
    'nl-NL',
    'x',
  );
  test('a spoken distance: one kilometer is not "1 kilometers"', () {
    expect(en.withDistance(1020, 'Turn left.'), contains('1 kilometer,'));
    expect(en.withDistance(2400, 'Turn left.'), contains('2.4 kilometers'));
    expect(nl.withDistance(1020, 'Sla linksaf.'), contains('1 kilometer'));
    // Rounded to 50 m this would have been "1000 meters".
    expect(en.withDistance(990, 'Turn left.'), contains('1 kilometer,'));
    expect(en.withDistance(940, 'Turn left.'), contains('950 meters'));
  });
}
