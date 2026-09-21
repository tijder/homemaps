import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/utils/afstand.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  test('hemelsbrede afstand', () {
    // Dom (Utrecht) -> Dam (Amsterdam): ongeveer 35 km.
    expect(
      meters(const LatLng(52.0907, 5.1214), const LatLng(52.3731, 4.8922)),
      closeTo(35100, 300),
    );
    expect(meters(const LatLng(52, 5), const LatLng(52, 5)), 0);
    // Een honderdduizendste graad breedte is ruim een meter.
    expect(
      meters(const LatLng(52, 5), const LatLng(52.00001, 5)),
      closeTo(1.11, 0.01),
    );
  });
}
