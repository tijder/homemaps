import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/utils/snelheid_tijden.dart';

void main() {
  // Zoals de importer ze geeft: A27 bij Eemnes (130 na zeven uur), een weg met
  // alleen op werkdagen een spitsregel, en een nachtregel die op vrijdag
  // begint.
  final tijden = SnelheidTijden.uitJson({
    'ways': {
      '7014267': [
        [
          130,
          127,
          [
            [1140, 360],
          ],
        ],
      ],
      '2': [
        [
          80,
          31,
          [
            [420, 540],
            [960, 1140],
          ],
        ],
      ],
      '3': [
        [
          50,
          16,
          [
            [1320, 360],
          ],
        ],
      ],
      'onzin': [
        [130, 127, []],
      ],
      '4': 'geen lijst',
    },
  });

  // 28 september 2026 is een maandag.
  DateTime op(int dag, int uur, int minuut) =>
      DateTime(2026, 9, 27 + dag, uur, minuut);

  test('130 na zeven uur, tot zes uur in de ochtend', () {
    expect(tijden.limietOp(7014267, 100, op(1, 18, 59)), 100);
    expect(tijden.limietOp(7014267, 100, op(1, 19, 0)), 130);
    expect(tijden.limietOp(7014267, 100, op(2, 5, 59)), 130);
    expect(tijden.limietOp(7014267, 100, op(2, 6, 0)), 100);
    // Een andere way, of geen: gewoon de normale.
    expect(tijden.limietOp(99, 100, op(1, 22, 0)), 100);
    expect(tijden.limietOp(null, 100, op(1, 22, 0)), 100);
  });

  test('op werkdagen in de spits, niet in het weekend', () {
    expect(tijden.limietOp(2, 100, op(1, 8, 0)), 80); // maandag
    expect(tijden.limietOp(2, 100, op(5, 17, 30)), 80); // vrijdag
    expect(tijden.limietOp(2, 100, op(5, 12, 0)), 100);
    expect(tijden.limietOp(2, 100, op(6, 8, 0)), 100); // zaterdag
  });

  test('over middernacht: de dag waarop het venster begint telt', () {
    // Vrijdag 22:00 tot zaterdag 06:00.
    expect(tijden.limietOp(3, 80, op(5, 23, 0)), 50);
    expect(tijden.limietOp(3, 80, op(6, 3, 0)), 50);
    // Vrijdagochtend hoort bij donderdagnacht, en die telt niet.
    expect(tijden.limietOp(3, 80, op(5, 3, 0)), 80);
  });

  test('wat niet klopt wordt overgeslagen', () {
    expect(SnelheidTijden.uitJson(null).isEmpty, isTrue);
    expect(SnelheidTijden.uitJson({'ways': 'x'}).isEmpty, isTrue);
    expect(tijden.limietOp(4, 70, op(1, 22, 0)), 70);
  });
}
