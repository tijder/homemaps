import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/services/photon_service.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  final photon = PhotonService(Dio(), 'https://maps.test/geocode');

  test('vrij zoeken stuurt alleen parameters die Photon kent', () {
    final uri = photon.zoekUri(' Domplein ', nabij: const LatLng(52.09, 5.12));
    expect(uri.path, '/geocode');
    expect(uri.queryParameters['q'], 'Domplein');
    expect(uri.queryParametersAll['osm_tag'], hasLength(4));
    expect(uri.queryParameters['lat'], '52.09');
    expect(uri.queryParameters.keys.toSet(), {
      'q',
      'limit',
      'lang',
      'osm_tag',
      'lat',
      'lon',
    });
  });

  test('postcode met huisnummer gaat naar structured', () {
    final uri = photon.zoekUri('1273cv 20');
    expect(uri.path, '/geocode/structured');
    expect(uri.queryParameters['postcode'], '1273 CV');
    expect(uri.queryParameters['housenumber'], '20');
    expect(uri.queryParameters.containsKey('q'), isFalse);
  });

  test('een adres zonder name krijgt straat en huisnummer als naam', () {
    final plaatsen = PhotonService.leesAntwoord({
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
    expect(plaatsen[0].naam, 'De Haar 20');
    expect(plaatsen[0].omschrijving, '1273 CV, Huizen, Nederland');
    expect(plaatsen[0].punt, const LatLng(52.3, 5.2));
    expect(plaatsen[1].naam, 'Utrecht');
    expect(plaatsen[1].omschrijving, 'Nederland');
  });

  test('coördinaten worden niet opgezocht', () async {
    final gevonden = await photon.zoek('52.09, 5.12');
    expect(gevonden.single.punt, const LatLng(52.09, 5.12));
  });
}
