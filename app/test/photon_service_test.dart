import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/services/photon_service.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  final photon = PhotonService(Dio(), 'https://maps.test/geocode');

  test('free search only sends parameters Photon knows', () {
    final uri = photon.searchUri(' Domplein ', near: const LatLng(52.09, 5.12));
    expect(uri.path, '/geocode');
    expect(uri.queryParameters['q'], 'Domplein');
    expect(uri.queryParametersAll['osm_tag'], hasLength(4));
    expect(uri.queryParameters['lat'], '52.09');
    expect(uri.queryParameters['zoom'], '13');
    expect(uri.queryParameters.keys.toSet(), {
      'q',
      'limit',
      'lang',
      'osm_tag',
      'lat',
      'lon',
      'zoom',
    });
  });

  test('without a location no bias', () {
    final uri = photon.searchUri('Domplein');
    expect(uri.queryParameters.keys, isNot(contains('zoom')));
    expect(uri.queryParameters.keys, isNot(contains('lat')));
  });

  test('postcode with house number goes to structured', () {
    final uri = photon.searchUri('1273cv 20');
    expect(uri.path, '/geocode/structured');
    expect(uri.queryParameters['postcode'], '1273 CV');
    expect(uri.queryParameters['housenumber'], '20');
    expect(uri.queryParameters.containsKey('q'), isFalse);
  });

  test('an address without name gets street and house number as its name', () {
    final places = PhotonService.parseResponse({
      'features': [
        {
          'geometry': {
            'coordinates': [5.2, 52.3],
          },
          'properties': {
            'street': 'De Haar',
            'housenumber': '20',
            'postcode': '1273 CV',
            'city': 'Huizen',
            'country': 'Nederland',
          },
        },
        {
          'geometry': {
            'coordinates': [5.12, 52.09],
          },
          'properties': {
            'name': 'Utrecht',
            'city': 'Utrecht',
            'country': 'Nederland',
          },
        },
      ],
    });
    expect(places[0].label, 'De Haar 20');
    expect(places[0].description, '1273 CV, Huizen, Nederland');
    expect(places[0].point, const LatLng(52.3, 5.2));
    expect(places[1].label, 'Utrecht');
    expect(places[1].description, 'Nederland');
  });

  test('coordinates are not looked up', () async {
    final found = await photon.search('52.09, 5.12');
    expect(found.single.point, const LatLng(52.09, 5.12));
  });
}
