import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/locatie_delen.dart';

/// Eén HTTP-verzoek naar de server van de gebruiker.
class DeelVerzoek {
  const DeelVerzoek({
    required this.methode,
    required this.uri,
    this.headers = const {},
    this.body,
  });

  final DeelMethode methode;
  final Uri uri;
  final Map<String, String> headers;

  /// JSON (een Map); null bij GET.
  final Map<String, Object?>? body;
}

/// Hoeveel punten er in één verzoek gaan: bij Overland een batch, anders één.
int puntenPerVerzoek(DeelInstellingen instellingen) =>
    instellingen.sjabloon.batch ? 100 : 1;

/// Het verzoek voor [punten], in het formaat van het gekozen sjabloon -- zoals
/// Colota het stuurt. Zonder batch-sjabloon hoort er precies één punt in.
DeelVerzoek bouwVerzoek(DeelInstellingen instellingen, List<DeelPunt> punten) {
  assert(punten.isNotEmpty);
  final uri = Uri.parse(instellingen.url.trim());
  final headers = <String, String>{
    if (instellingen.inlog == DeelInlog.basic)
      'Authorization':
          'Basic ${base64Encode(utf8.encode('${instellingen.gebruiker}:${instellingen.geheim}'))}',
    if (instellingen.inlog == DeelInlog.bearer)
      'Authorization': 'Bearer ${instellingen.geheim}',
  };
  final extra = instellingen.extraVelden;

  if (instellingen.sjabloon.batch) {
    return DeelVerzoek(
      methode: DeelMethode.post,
      uri: uri,
      headers: headers,
      body: {
        'locations': [for (final p in punten) _overlandFeature(p)],
        for (final e in extra.entries)
          if (e.key != 'device_id') e.key: e.value,
        'device_id': extra['device_id'] ?? 'homemaps',
      },
    );
  }

  final punt = punten.single;
  if (instellingen.sjabloon == DeelSjabloon.traccar &&
      instellingen.methode == DeelMethode.post) {
    return DeelVerzoek(
      methode: DeelMethode.post,
      uri: uri,
      headers: headers,
      body: _traccarJson(punt, extra['id'] ?? extra['device_id'] ?? 'homemaps'),
    );
  }

  final velden = _plat(punt, instellingen.effectieveVelden);
  final alles = <String, Object?>{...velden, ...extra};
  if (instellingen.methode == DeelMethode.get) {
    return DeelVerzoek(
      methode: DeelMethode.get,
      uri: uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          for (final e in alles.entries) e.key: '${e.value}',
        },
      ),
      headers: headers,
    );
  }
  return DeelVerzoek(
    methode: DeelMethode.post,
    uri: uri,
    headers: headers,
    body: alles,
  );
}

/// De basisvelden onder hun naam bij dit sjabloon; afgerond zoals Colota.
Map<String, Object> _plat(DeelPunt p, Map<String, String> namen) => {
  namen['lat']!: p.lat,
  namen['lon']!: p.lon,
  namen['acc']!: ?p.acc?.round(),
  namen['alt']!: ?p.alt?.round(),
  if (p.vel case final vel?) namen['vel']!: (vel * 10).round() / 10,
  namen['tst']!: p.tst,
  namen['bear']!: ?p.bear,
};

String _iso(int tst) => DateTime.fromMillisecondsSinceEpoch(
  tst * 1000,
  isUtc: true,
).toIso8601String().replaceFirst('.000', '');

Map<String, Object?> _overlandFeature(DeelPunt p) => {
  'type': 'Feature',
  'geometry': {
    'type': 'Point',
    'coordinates': [p.lon, p.lat],
  },
  'properties': {
    'timestamp': _iso(p.tst),
    'horizontal_accuracy': ?p.acc?.round(),
    'altitude': ?p.alt?.round(),
    'speed': ?p.vel,
    'course': ?p.bear,
  },
};

/// Traccar 6.7+ (OsmAnd-protocol als JSON).
Map<String, Object?> _traccarJson(DeelPunt p, String apparaat) => {
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
  'device_id': apparaat,
};

/// Stuurt een [DeelVerzoek] en geeft de HTTP-status; gooit bij geen verbinding.
abstract class DeelVerzender {
  Future<int> stuur(DeelVerzoek verzoek);
}

class DioVerzender implements DeelVerzender {
  DioVerzender(this._dio);

  final Dio _dio;

  @override
  Future<int> stuur(DeelVerzoek verzoek) async {
    final antwoord = await _dio.requestUri<Object?>(
      verzoek.uri,
      data: verzoek.body,
      options: Options(
        method: verzoek.methode == DeelMethode.get ? 'GET' : 'POST',
        headers: verzoek.headers,
        contentType: verzoek.body == null ? null : Headers.jsonContentType,
        responseType: ResponseType.plain,
        // De status beoordeelt de deler zelf.
        validateStatus: (_) => true,
      ),
    );
    return antwoord.statusCode ?? 0;
  }
}
