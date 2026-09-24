import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/utils/distance.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  test('straight-line distance', () {
    // Dom (Utrecht) -> Dam (Amsterdam): about 35 km.
    expect(
      meters(const LatLng(52.0907, 5.1214), const LatLng(52.3731, 4.8922)),
      closeTo(35100, 300),
    );
    expect(meters(const LatLng(52, 5), const LatLng(52, 5)), 0);
    // A hundred-thousandth of a degree of latitude is just over a metre.
    expect(
      meters(const LatLng(52, 5), const LatLng(52.00001, 5)),
      closeTo(1.11, 0.01),
    );
  });
}
