import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/utils/zoekterm.dart';

void main() {
  test('postcode met huisnummer in al zijn schrijfwijzen', () {
    for (final tekst in [
      '1273 CV 20',
      '1273CV 20',
      '1273cv,20',
      ' 1273CV20 ',
    ]) {
      final adres = leesPostcodeHuisnummer(tekst);
      expect(adres?.postcode, '1273 CV', reason: tekst);
      expect(adres?.huisnummer, '20', reason: tekst);
    }
    expect(leesPostcodeHuisnummer('1273 CV 20-a')?.huisnummer, '20-a');
    expect(leesPostcodeHuisnummer('1273 CV'), isNull);
    expect(leesPostcodeHuisnummer('De Haar 20'), isNull);
  });

  test('coördinaten, maar geen postcodes', () {
    expect(leesCoordinaat('52.09, 5.12')?.latitude, 52.09);
    // LatLng normaliseert de lengtegraad, dus geen exacte vergelijking.
    expect(leesCoordinaat('52.09 5.12')?.longitude, closeTo(5.12, 1e-9));
    expect(leesCoordinaat('-33.9;18.4')?.latitude, -33.9);
    // Dit las de oorspronkelijke UI als coördinaat.
    expect(leesCoordinaat('1273CV 20'), isNull);
    expect(leesCoordinaat('1273 20'), isNull);
    expect(leesCoordinaat('95.0, 5.0'), isNull);
  });
}
