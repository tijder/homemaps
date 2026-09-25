import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/widgets/traffic_incident.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('nl'));
  (String, List<String>) text(Map<String, dynamic> info) =>
      TrafficIncident.text(l, 'nl', info);

  setUpAll(() => initializeDateFormatting('nl'));

  test('closure: the carriageway in the title, cause and end below', () {
    final (title, lines) = text({
      'kind': 'closed',
      'whole_road': false,
      'carriageway': 'entrySlipRoad',
      'cause': 'roadMaintenance',
      'until': '2026-10-22T18:00:00Z',
    });
    expect(title, 'Oprit afgesloten');
    expect(lines.first, 'Werkzaamheden');
    // In the device's local time; the tests don't run in NL everywhere.
    expect(lines.last, startsWith('Tot '));
    expect(lines.last, contains('okt'));
  });

  test('roadClosed beats the carriageway', () {
    final (title, _) = text({
      'kind': 'closed',
      'whole_road': true,
      'carriageway': 'exitSlipRoad',
    });
    expect(title, 'Weg afgesloten');
  });

  test('roadworks with open lanes; unknown cause is left out', () {
    final (title, lines) = text({
      'kind': 'roadworks',
      'lanes_open': 1,
      'cause': 'other',
    });
    expect(title, 'Rijstrook afgesloten');
    expect(lines, ['1 rijstrook open']);
  });

  test('jam: delay and speed', () {
    final (title, lines) = text({'kind': 'jam', 'delay_s': 540, 'kph': 23});
    expect(title, 'File');
    expect(lines, ['+9 min vertraging · 23 km/u']);
  });

  test('speed cameras: kind in the title, the checked speed below', () {
    final (title, lines) = text({'kind': 'speed_camera', 'maxspeed': 80});
    expect(title, 'Flitspaal');
    expect(lines, ['Controleert op 80 km/u']);
    expect(text({'kind': 'red_light'}).$2, isEmpty);
    expect(text({'kind': 'red_light'}).$1, 'Roodlichtcamera');
    expect(text({'kind': 'section_start'}).$1, 'Begin trajectcontrole');
    expect(text({'kind': 'section_end'}).$1, 'Einde trajectcontrole');
  });
}
