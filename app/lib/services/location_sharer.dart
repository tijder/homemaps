import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/location_sharing.dart';

/// One HTTP request to the user's server.
class ShareRequest {
  const ShareRequest({
    required this.method,
    required this.uri,
    this.headers = const {},
    this.body,
  });

  final ShareMethod method;
  final Uri uri;
  final Map<String, String> headers;

  /// JSON (a Map); null for GET.
  final Map<String, Object?>? body;
}

/// How many points go in one request: a batch for Overland, otherwise one.
int pointsPerRequest(ShareSettings settings) =>
    settings.template.batch ? 100 : 1;

/// The request for [points], in the chosen template's format -- as Colota
/// sends it. Without a batch template it holds exactly one point.
ShareRequest buildRequest(ShareSettings settings, List<SharedPoint> points) {
  assert(points.isNotEmpty);
  final uri = Uri.parse(settings.url.trim());
  final headers = <String, String>{
    if (settings.auth == ShareAuth.basic)
      'Authorization':
          'Basic ${base64Encode(utf8.encode('${settings.username}:${settings.secret}'))}',
    if (settings.auth == ShareAuth.bearer)
      'Authorization': 'Bearer ${settings.secret}',
  };
  final extra = settings.extraFields;

  if (settings.template.batch) {
    return ShareRequest(
      method: ShareMethod.post,
      uri: uri,
      headers: headers,
      body: {
        'locations': [
          for (final p in points)
            _overlandFeature(p, extra['device_id'] ?? 'homemaps'),
        ],
        for (final e in extra.entries)
          if (e.key != 'device_id') e.key: e.value,
        'device_id': extra['device_id'] ?? 'homemaps',
      },
    );
  }

  final point = points.single;
  if (settings.template == ShareTemplate.traccar &&
      settings.method == ShareMethod.post) {
    return ShareRequest(
      method: ShareMethod.post,
      uri: uri,
      headers: headers,
      body: _traccarJson(
        point,
        extra['id'] ?? extra['device_id'] ?? 'homemaps',
      ),
    );
  }

  final fields = _flatten(point, settings.effectiveFields);
  final everything = <String, Object?>{...fields, ...extra};
  if (settings.method == ShareMethod.get) {
    return ShareRequest(
      method: ShareMethod.get,
      uri: uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          for (final e in everything.entries) e.key: '${e.value}',
        },
      ),
      headers: headers,
    );
  }
  return ShareRequest(
    method: ShareMethod.post,
    uri: uri,
    headers: headers,
    body: everything,
  );
}

/// The base fields under their names for this template; rounded like Colota.
Map<String, Object> _flatten(SharedPoint p, Map<String, String> names) => {
  names['lat']!: p.lat,
  names['lon']!: p.lon,
  names['acc']!: ?p.acc?.round(),
  names['alt']!: ?p.alt?.round(),
  if (p.vel case final vel?) names['vel']!: (vel * 10).round() / 10,
  names['tst']!: p.tst,
  names['bear']!: ?p.bear,
};

String _iso(int tst) => DateTime.fromMillisecondsSinceEpoch(
  tst * 1000,
  isUtc: true,
).toIso8601String().replaceFirst('.000', '');

/// One point as a GeoJSON feature, with Overland's properties. Dawarich reads
/// the same names (`/api/v1/points`), and `device_id` per point.
Map<String, Object?> _overlandFeature(SharedPoint p, String device) => {
  'type': 'Feature',
  'geometry': {
    'type': 'Point',
    'coordinates': [p.lon, p.lat],
  },
  'properties': {
    'timestamp': _iso(p.tst),
    'horizontal_accuracy': ?p.acc?.round(),
    'altitude': ?p.alt?.round(),
    'vertical_accuracy': ?p.vac?.round(),
    'speed': ?p.vel,
    'course': ?p.bear,
    'course_accuracy': ?p.bearAcc?.round(),
    'battery_level': ?(p.batt == null ? null : p.batt! / 100),
    'battery_state': ?p.bs,
    'motion': ?(p.transport == null ? null : [p.transport!]),
    'device_id': device,
  },
};

/// Traccar 6.7+ (OsmAnd protocol as JSON).
Map<String, Object?> _traccarJson(SharedPoint p, String device) => {
  'location': {
    'timestamp': _iso(p.tst),
    'coords': {
      'latitude': p.lat,
      'longitude': p.lon,
      'accuracy': ?p.acc,
      'altitude': ?p.alt,
      'speed': ?p.vel,
      'heading': ?p.bear,
    },
  },
  'device_id': device,
};

/// Sends a [ShareRequest] and returns the HTTP status; throws without a
/// connection.
abstract class ShareSender {
  Future<int> send(ShareRequest request);
}

class DioSender implements ShareSender {
  DioSender(this._dio);

  final Dio _dio;

  @override
  Future<int> send(ShareRequest request) async {
    final response = await _dio.requestUri<Object?>(
      request.uri,
      data: request.body,
      options: Options(
        method: request.method == ShareMethod.get ? 'GET' : 'POST',
        headers: request.headers,
        contentType: request.body == null ? null : Headers.jsonContentType,
        responseType: ResponseType.plain,
        // The sharer judges the status itself.
        validateStatus: (_) => true,
      ),
    );
    return response.statusCode ?? 0;
  }
}
