import 'dart:async';

import 'package:dio/dio.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/profiel.dart';
import '../models/route.dart';

class RouteFout implements Exception {
  RouteFout(this.code, this.melding);

  /// Valhalla's `error_code` (442 = geen route gevonden, 171 = geen weg in de
  /// buurt van een punt), of 0 bij een netwerkfout.
  final int code;
  final String melding;

  @override
  String toString() => 'RouteFout($code): $melding';
}

class ValhallaService {
  ValhallaService(this._dio, this.basis);

  final Dio _dio;

  /// Bijvoorbeeld `https://maps.example.org/valhalla`.
  final String basis;

  static const hoogteInterval = 30.0;

  /// Het verzoek als JSON. Los van [route] zodat het te testen is.
  static Map<String, dynamic> verzoek(
    List<LatLng> punten,
    Profiel profiel, {
    required String taal,
    bool liveVerkeer = true,
    bool vermijdSnelwegen = false,
    bool vermijdTol = false,
    bool vermijdVeren = false,
    bool alternatieven = true,
    double? koers,
    DateTime? nu,
  }) {
    final opties = <String, dynamic>{
      if (vermijdSnelwegen) 'use_highways': 0.0,
      if (vermijdTol) 'use_tolls': 0.0,
      if (vermijdVeren) 'use_ferry': 0.0,
    };
    return {
      'locations': [
        for (final (i, punt) in punten.indexed)
          {
            'lat': punt.latitude,
            'lon': punt.longitude,
            // Een via-punt is een plek waar je langs wilt, geen tussenstop:
            // `through` staat geen keren op de weg toe.
            'type': i == 0 || i == punten.length - 1 ? 'break' : 'through',
            // Onderweg herberekend: vertrek in de richting waarin je rijdt, niet
            // met een U-bocht omdat het andersom een paar meter korter is.
            if (i == 0 && koers != null) ...{
              'heading': koers.round() % 360,
              'heading_tolerance': 45,
            },
          },
      ],
      'costing': profiel.costing,
      if (opties.isNotEmpty) 'costing_options': {profiel.costing: opties},
      'units': 'kilometers',
      'language': taal,
      'elevation_interval': hoogteInterval,
      // Valhalla geeft alleen alternatieven tussen precies twee punten.
      if (alternatieven && punten.length == 2) 'alternates': 2,
      // Live verkeer (snelheden én afsluitingen) telt alleen met een vertrektijd
      // van nu, en alleen voor de auto. Niet `type: 0` ("vertrek nu"): dat gaat
      // langs de eenrichtingszoeker, en die geeft geen alternatieven. `type: 3`
      // (één vaste tijd voor de hele route) gaat langs de tweerichtingszoeker
      // en leest het live verkeer net zo goed -- zolang de tijd echt nu is.
      // Valhalla leest hem als lokale tijd op het vertrekpunt.
      if (liveVerkeer && profiel == Profiel.auto)
        'date_time': {'type': 3, 'value': _minuut(nu ?? DateTime.now())},
    };
  }

  static String _minuut(DateTime tijd) {
    String twee(int n) => n.toString().padLeft(2, '0');
    return '${tijd.year}-${twee(tijd.month)}-${twee(tijd.day)}'
        'T${twee(tijd.hour)}:${twee(tijd.minute)}';
  }

  Future<List<RouteOptie>> route(
    List<LatLng> punten,
    Profiel profiel, {
    required String taal,
    bool liveVerkeer = true,
    bool vermijdSnelwegen = false,
    bool vermijdTol = false,
    bool vermijdVeren = false,
    bool alternatieven = true,
    double? koers,
    CancelToken? annuleer,
  }) async {
    try {
      final antwoord = await _dio.post<Map<String, dynamic>>(
        '$basis/route',
        data: verzoek(
          punten,
          profiel,
          taal: taal,
          liveVerkeer: liveVerkeer,
          vermijdSnelwegen: vermijdSnelwegen,
          vermijdTol: vermijdTol,
          vermijdVeren: vermijdVeren,
          alternatieven: alternatieven,
          koers: koers,
        ),
        cancelToken: annuleer,
      );
      return leesAntwoord(antwoord.data ?? const {});
    } on DioException catch (fout) {
      if (CancelToken.isCancel(fout)) rethrow;
      throw _routeFout(fout);
    }
  }

  static RouteFout _routeFout(DioException fout) {
    final data = fout.response?.data;
    if (data is Map && data['error'] != null) {
      return RouteFout(
        (data['error_code'] as num?)?.toInt() ?? 0,
        data['error'].toString(),
      );
    }
    return RouteFout(0, fout.message ?? fout.type.name);
  }

  static List<RouteOptie> leesAntwoord(Map<String, dynamic> json) => [
    RouteOptie.vanValhalla(
      (json['trip'] as Map).cast<String, dynamic>(),
      hoogteInterval: hoogteInterval,
    ),
    for (final alternatief in (json['alternates'] as List? ?? const []))
      RouteOptie.vanValhalla(
        ((alternatief as Map)['trip'] as Map).cast<String, dynamic>(),
        hoogteInterval: hoogteInterval,
      ),
  ];
}
