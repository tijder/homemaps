import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/widgets/verkeer_melding.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('nl'));
  (String, List<String>) tekst(Map<String, dynamic> info) =>
      VerkeerMelding.tekst(l, 'nl', info);

  setUpAll(() => initializeDateFormatting('nl'));

  test('afsluiting: de rijbaan in de titel, oorzaak en einde eronder', () {
    final (titel, regels) = tekst({
      'soort': 'dicht',
      'hele_weg': false,
      'rijbaan': 'entrySlipRoad',
      'oorzaak': 'roadMaintenance',
      'tot': '2026-10-22T18:00:00Z',
    });
    expect(titel, 'Oprit afgesloten');
    expect(regels.first, 'Werkzaamheden');
    // In de lokale tijd van het apparaat; de tests draaien niet overal in NL.
    expect(regels.last, startsWith('Tot '));
    expect(regels.last, contains('okt'));
  });

  test('roadClosed wint van de rijbaan', () {
    final (titel, _) = tekst({
      'soort': 'dicht',
      'hele_weg': true,
      'rijbaan': 'exitSlipRoad',
    });
    expect(titel, 'Weg afgesloten');
  });

  test('werk met open rijstroken; onbekende oorzaak blijft weg', () {
    final (titel, regels) = tekst({
      'soort': 'werk',
      'stroken_open': 1,
      'oorzaak': 'other',
    });
    expect(titel, 'Rijstrook afgesloten');
    expect(regels, ['1 rijstrook open']);
  });

  test('file: vertraging en snelheid', () {
    final (titel, regels) = tekst({
      'soort': 'file',
      'vertraging_s': 540,
      'kmu': 23,
    });
    expect(titel, 'File');
    expect(regels, ['+9 min vertraging · 23 km/u']);
  });
}
