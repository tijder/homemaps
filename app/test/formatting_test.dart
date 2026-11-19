import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
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
