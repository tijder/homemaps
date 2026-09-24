import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/utils/search_term.dart';

void main() {
  test('postcode with house number in all its spellings', () {
    for (final text in ['1273 CV 20', '1273CV 20', '1273cv,20', ' 1273CV20 ']) {
      final address = parsePostcodeHouseNumber(text);
      expect(address?.postcode, '1273 CV', reason: text);
      expect(address?.houseNumber, '20', reason: text);
    }
    expect(parsePostcodeHouseNumber('1273 CV 20-a')?.houseNumber, '20-a');
    expect(parsePostcodeHouseNumber('1273 CV'), isNull);
    expect(parsePostcodeHouseNumber('De Haar 20'), isNull);
  });

  test('coordinates, but no postcodes', () {
    expect(parseCoordinate('52.09, 5.12')?.latitude, 52.09);
    // LatLng normalises the longitude, so no exact comparison.
    expect(parseCoordinate('52.09 5.12')?.longitude, closeTo(5.12, 1e-9));
    expect(parseCoordinate('-33.9;18.4')?.latitude, -33.9);
    // The original UI read this as a coordinate.
    expect(parseCoordinate('1273CV 20'), isNull);
    expect(parseCoordinate('1273 20'), isNull);
    expect(parseCoordinate('95.0, 5.0'), isNull);
  });
}
