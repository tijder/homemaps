import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/utils/geo_link.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

GeoRequest? read(String link) => parseGeoLink(Uri.parse(link));

void main() {
  test('geo with coordinates', () {
    expect(read('geo:52.0907,5.1214')?.point, const LatLng(52.0907, 5.1214));
    expect(
      read('geo:52.0907,5.1214?z=15')?.point,
      const LatLng(52.0907, 5.1214),
    );
    expect(read('geo:-33.86,151.2')?.point, const LatLng(-33.86, 151.2));
  });

  test('geo with q: a point with a name, or an address', () {
    final bakery = read('geo:0,0?q=52.1,5.2(Bakker%20Jansen)')!;
    expect(bakery.point, const LatLng(52.1, 5.2));
    expect(bakery.label, 'Bakker Jansen');
    final address = read('geo:0,0?q=Stationsplein+1%2C+Utrecht')!;
    expect(address.point, isNull);
    expect(address.search, 'Stationsplein 1, Utrecht');
    expect(address.navigate, isFalse);
  });

  test('google.navigation: a route right away', () {
    final point = read('google.navigation:q=52.1,5.2')!;
    expect(point.point, const LatLng(52.1, 5.2));
    expect(point.navigate, isTrue);
    expect(
      read('google.navigation:q=Utrecht+Centraal')?.search,
      'Utrecht Centraal',
    );
  });

  test('nonsense and other schemes: null', () {
    expect(read('geo:0,0'), isNull);
    expect(read('geo:hello'), isNull);
    expect(read('geo:95,5'), isNull);
    expect(read('https://example.org/?q=52.1,5.2'), isNull);
  });
}
