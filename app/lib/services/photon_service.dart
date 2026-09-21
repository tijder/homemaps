import 'package:dio/dio.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/plaats.dart';
import '../utils/zoekterm.dart';

class PhotonService {
  PhotonService(this._dio, this.basis);

  final Dio _dio;

  /// Bijvoorbeeld `https://maps.example.org/geocode`.
  final String basis;

  /// De URI van een zoekopdracht. Los van [zoek] zodat hij te testen is: Photon
  /// weigert elke parameter die hij niet kent met een 400.
  Uri zoekUri(String tekst, {LatLng? nabij}) {
    final adres = leesPostcodeHuisnummer(tekst);
    final parameters = <String, dynamic>{
      if (adres != null) ...{
        'postcode': adres.postcode,
        'housenumber': adres.huisnummer,
      } else
        'q': tekst.trim(),
      'limit': '10',
      // De kant-en-klare landindexen kennen alleen default, de, en en fr;
      // `default` is de lokale naam.
      'lang': 'default',
      // Tussen gebieden routeren heeft geen zin, en toeristische bordjes zijn
      // geen bestemming.
      'osm_tag': ['!place:county', '!boundary', '!historic', '!information'],
      if (nabij != null) ...{
        'lat': nabij.latitude.toString(),
        'lon': nabij.longitude.toString(),
      },
    };
    final uri = Uri.parse(adres != null ? '$basis/structured' : basis);
    return uri.replace(queryParameters: parameters);
  }

  Future<List<Plaats>> zoek(
    String tekst, {
    LatLng? nabij,
    CancelToken? annuleer,
  }) async {
    if (tekst.trim().length < 2) return const [];
    final punt = leesCoordinaat(tekst);
    if (punt != null) return [Plaats.vanPunt(punt)];
    final antwoord = await _dio.getUri<Map<String, dynamic>>(
      zoekUri(tekst, nabij: nabij),
      cancelToken: annuleer,
    );
    return leesAntwoord(antwoord.data ?? const {});
  }

  /// Het adres bij een punt, of null als Photon er geen kent.
  Future<Plaats?> omgekeerd(LatLng punt) async {
    final antwoord = await _dio.getUri<Map<String, dynamic>>(
      Uri.parse('$basis/reverse').replace(
        queryParameters: {
          'lat': punt.latitude.toString(),
          'lon': punt.longitude.toString(),
          'lang': 'default',
        },
      ),
    );
    final gevonden = leesAntwoord(antwoord.data ?? const {});
    if (gevonden.isEmpty) return null;
    // Het punt blijft waar de gebruiker tikte; alleen de naam komt van Photon.
    return Plaats(
      naam: gevonden.first.naam,
      omschrijving: gevonden.first.omschrijving,
      punt: punt,
    );
  }

  static List<Plaats> leesAntwoord(Map<String, dynamic> json) => [
    for (final feature in (json['features'] as List? ?? const []))
      Plaats.vanPhoton((feature as Map).cast<String, dynamic>()),
  ];
}
