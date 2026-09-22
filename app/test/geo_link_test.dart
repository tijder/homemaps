import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/utils/geo_link.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

GeoVerzoek? lees(String link) => leesGeoLink(Uri.parse(link));

void main() {
  test('geo met coördinaten', () {
    expect(lees('geo:52.0907,5.1214')?.punt, const LatLng(52.0907, 5.1214));
    expect(
      lees('geo:52.0907,5.1214?z=15')?.punt,
      const LatLng(52.0907, 5.1214),
    );
    expect(lees('geo:-33.86,151.2')?.punt, const LatLng(-33.86, 151.2));
  });

  test('geo met q: een punt met naam, of een adres', () {
    final bakker = lees('geo:0,0?q=52.1,5.2(Bakker%20Jansen)')!;
    expect(bakker.punt, const LatLng(52.1, 5.2));
    expect(bakker.label, 'Bakker Jansen');
    final adres = lees('geo:0,0?q=Stationsplein+1%2C+Utrecht')!;
    expect(adres.punt, isNull);
    expect(adres.zoek, 'Stationsplein 1, Utrecht');
    expect(adres.navigeer, isFalse);
  });

  test('google.navigation: meteen een route', () {
    final punt = lees('google.navigation:q=52.1,5.2')!;
    expect(punt.punt, const LatLng(52.1, 5.2));
    expect(punt.navigeer, isTrue);
    expect(
      lees('google.navigation:q=Utrecht+Centraal')?.zoek,
      'Utrecht Centraal',
    );
  });

  test('onzin en andere schema\'s: null', () {
    expect(lees('geo:0,0'), isNull);
    expect(lees('geo:hallo'), isNull);
    expect(lees('geo:95,5'), isNull);
    expect(lees('https://example.org/?q=52.1,5.2'), isNull);
  });
}
