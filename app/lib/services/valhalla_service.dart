import 'dart:async';

import 'package:dio/dio.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/profiel.dart';
import '../models/route.dart';
import '../utils/polyline.dart';

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
      final routes = leesAntwoord(antwoord.data ?? const {});
      final metVerkeer = liveVerkeer && profiel == Profiel.auto;
      if (!metVerkeer) return routes;
      // Tegelijk voor elke route: hoe lang dezelfde weg zonder verkeer duurt.
      final normaal = await Future.wait([
        for (final route in routes) normaleTijd(route, profiel, annuleer),
      ]);
      return [
        for (final (i, route) in routes.indexed)
          route.metNormaleTijd(normaal[i]),
      ];
    } on DioException catch (fout) {
      if (CancelToken.isCancel(fout)) rethrow;
      throw _routeFout(fout);
    }
  }

  /// De reistijd van precies deze weg zonder live verkeer: zie [reistijd].
  Future<double?> normaleTijd(
    RouteOptie route,
    Profiel profiel, [
    CancelToken? annuleer,
  ]) => reistijd(route.punten, profiel, annuleer: annuleer);

  /// De reistijd over precies deze lijn: Valhalla legt hem opnieuw op de kaart
  /// (edge_walk: exact dezelfde wegen). [live]: met het verkeer van nu, anders
  /// zonder. Twee lijnen met dezelfde [live] zijn zo eerlijk te vergelijken --
  /// een tijd uit /route rekent net iets anders. Null als het mislukt.
  Future<double?> reistijd(
    List<LatLng> lijn,
    Profiel profiel, {
    bool live = false,
    DateTime? nu,
    CancelToken? annuleer,
  }) async {
    // Tussen twee legs staat hetzelfde punt twee keer; eruit.
    final punten = <LatLng>[];
    for (final punt in lijn) {
      if (punten.isEmpty || punten.last != punt) punten.add(punt);
    }
    if (punten.length < 2) return null;
    try {
      final antwoord = await _dio.post<Map<String, dynamic>>(
        '$basis/trace_route',
        data: {
          'encoded_polyline': codeerPolyline(punten),
          'costing': profiel.costing,
          'shape_match': 'edge_walk',
          'directions_type': 'none',
          if (live)
            'date_time': {'type': 3, 'value': _minuut(nu ?? DateTime.now())},
        },
        cancelToken: annuleer,
      );
      final tijd = antwoord.data?['trip']?['summary']?['time'];
      return tijd is num ? tijd.toDouble() : null;
    } on DioException catch (fout) {
      if (CancelToken.isCancel(fout)) rethrow;
      return null;
    }
  }

  /// De maximumsnelheid (km/u) per stuk van [lijn]: element i hoort bij het
  /// stuk van punt i naar i+1, null als die onbekend is. Null als het hele
  /// verzoek mislukt.
  Future<List<int?>?> snelheidsLimieten(
    List<LatLng> lijn,
    Profiel profiel, {
    CancelToken? annuleer,
  }) async {
    // Dubbele punten (tussen twee legs) eruit, maar onthouden waar elk
    // oorspronkelijk punt terechtkwam.
    final punten = <LatLng>[];
    final naar = <int>[];
    for (final punt in lijn) {
      if (punten.isEmpty || punten.last != punt) punten.add(punt);
      naar.add(punten.length - 1);
    }
    if (punten.length < 2) return null;
    try {
      final antwoord = await _dio.post<Map<String, dynamic>>(
        '$basis/trace_attributes',
        data: {
          'encoded_polyline': codeerPolyline(punten),
          'costing': profiel.costing,
          'shape_match': 'edge_walk',
          'filters': {
            'attributes': [
              'edge.speed_limit',
              'edge.begin_shape_index',
              'edge.end_shape_index',
            ],
            'action': 'include',
          },
        },
        cancelToken: annuleer,
      );
      final perStuk = List<int?>.filled(punten.length - 1, null);
      for (final edge in (antwoord.data?['edges'] as List? ?? const [])) {
        if (edge is! Map) continue;
        final limiet = edge['speed_limit'];
        final begin = edge['begin_shape_index'], eind = edge['end_shape_index'];
        // Onbekend is 0 of ontbreekt; "unlimited" (Duitse snelweg) is een tekst.
        if (limiet is! num || limiet <= 0 || begin is! num || eind is! num) {
          continue;
        }
        for (
          var i = begin.toInt();
          i < eind.toInt() && i < perStuk.length;
          i++
        ) {
          perStuk[i] = limiet.round();
        }
      }
      return [
        for (var i = 0; i < lijn.length - 1; i++)
          perStuk[naar[i].clamp(0, perStuk.length - 1)],
      ];
    } on DioException catch (fout) {
      if (CancelToken.isCancel(fout)) rethrow;
      return null;
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
