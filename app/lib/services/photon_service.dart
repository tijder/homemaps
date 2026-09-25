import 'package:dio/dio.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/place.dart';
import '../utils/search_term.dart';

class PhotonService {
  PhotonService(this._dio, this.baseUrl);

  final Dio _dio;

  /// For example `https://maps.example.org/geocode`.
  final String baseUrl;

  /// The URI of a search. Separate from [search] so it can be tested: Photon
  /// rejects every parameter it doesn't know with a 400.
  Uri searchUri(String text, {LatLng? near}) {
    final address = parsePostcodeHouseNumber(text);
    final parameters = <String, dynamic>{
      if (address != null) ...{
        'postcode': address.postcode,
        'housenumber': address.houseNumber,
      } else
        'q': text.trim(),
      'limit': '10',
      // The ready-made country indexes only know default, de, en and fr;
      // `default` is the local name.
      'lang': 'default',
      // Routing between regions makes no sense, and tourist signs aren't a
      // destination.
      'osm_tag': ['!place:county', '!boundary', '!historic', '!information'],
      if (near != null) ...{
        'lat': near.latitude.toString(),
        'lon': near.longitude.toString(),
        // How far the bias reaches. Photon's default (16, a few km) fades out
        // so fast that a chain like "albert heijn" falls back to the most
        // prominent branches, in Amsterdam; at 13 the nearest ones win, while
        // "amsterdam" or "domplein" still find the city and the square.
        'zoom': '13',
      },
    };
    final uri = Uri.parse(address != null ? '$baseUrl/structured' : baseUrl);
    return uri.replace(queryParameters: parameters);
  }

  Future<List<Place>> search(
    String text, {
    LatLng? near,
    CancelToken? cancel,
  }) async {
    if (text.trim().length < 2) return const [];
    final point = parseCoordinate(text);
    if (point != null) return [Place.fromPoint(point)];
    final response = await _dio.getUri<Map<String, dynamic>>(
      searchUri(text, near: near),
      cancelToken: cancel,
    );
    return parseResponse(response.data ?? const {});
  }

  /// The address at a point, or null if Photon doesn't know one.
  Future<Place?> reverseGeocode(LatLng point) async {
    final response = await _dio.getUri<Map<String, dynamic>>(
      Uri.parse('$baseUrl/reverse').replace(
        queryParameters: {
          'lat': point.latitude.toString(),
          'lon': point.longitude.toString(),
          'lang': 'default',
        },
      ),
    );
    final found = parseResponse(response.data ?? const {});
    if (found.isEmpty) return null;
    // The point stays where the user tapped; only the name comes from Photon.
    return Place(
      label: found.first.label,
      description: found.first.description,
      point: point,
    );
  }

  static List<Place> parseResponse(Map<String, dynamic> json) => [
    for (final feature in (json['features'] as List? ?? const []))
      Place.fromPhoton((feature as Map).cast<String, dynamic>()),
  ];
}
