import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/widgets/kaart.dart';

void main() {
  test('de eerste tekstlaag van een stijl', () {
    expect(
      eersteTekstlaag(
        jsonEncode({
          'layers': [
            {'id': 'background', 'type': 'background'},
            {'id': 'highway-motorway', 'type': 'line'},
            {'id': 'road_oneway', 'type': 'symbol'},
            {'id': 'highway-shield', 'type': 'symbol'},
          ],
        }),
      ),
      'road_oneway',
    );
    expect(
      eersteTekstlaag(
        jsonEncode({
          'layers': [
            {'id': 'water', 'type': 'fill'},
          ],
        }),
      ),
      isNull,
    );
    expect(eersteTekstlaag(null), isNull);
    expect(eersteTekstlaag('geen json'), isNull);
  });
}
