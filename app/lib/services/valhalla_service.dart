import 'dart:async';

import 'package:dio/dio.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/profiel.dart';
import '../models/route.dart';
import '../utils/polyline.dart';
import '../utils/snelheid_tijden.dart';

class RouteFout implements Exception {
  RouteFout(this.code, this.melding);

  /// Valhalla's `error_code` (442 = geen route gevonden, 171 = geen weg in de
  /// buurt van een punt), of 0 bij een netwerkfout.
  final int code;
  final String melding;

  @override
  String toString() => 'RouteFout($code): $melding';
}

/// De maximumsnelheid (km/u, null als onbekend) en de OSM-way van een stuk
/// route.
typedef StukLimiet = ({int? limiet, int? way});

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
    final live = liveVerkeer && profiel == Profiel.auto;
    final opties = <String, dynamic>{
      if (vermijdSnelwegen) 'use_highways': 0.0,
      if (vermijdTol) 'use_tolls': 0.0,
      if (vermijdVeren) 'use_ferry': 0.0,
      // Wel een tijd (zie date_time hieronder), maar zonder het verkeer van nu:
      // alleen de gewone snelheden.
      if (profiel == Profiel.auto && !live)
        'speed_types': ['freeflow', 'constrained', 'predicted'],
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
      // Altijd een tijd: Valhalla houdt tijdgebonden toegang (schoolstraten,
      // venstertijden) alleen aan als hij weet wanneer je rijdt; zonder tijd
      // rijdt hij er dwars doorheen. Niet `type: 0` ("vertrek nu"): dat gaat
      // langs de eenrichtingszoeker, en die geeft geen alternatieven. `type: 3`
      // (één vaste tijd voor de hele route) gaat langs de tweerichtingszoeker.
      // Live verkeer (snelheden én afsluitingen) telt alleen met een tijd van
      // nu, en alleen voor de auto (anders zet `speed_types` het uit); met een
      // latere tijd ([nu]) laat Valhalla het vanzelf wegvallen naarmate het
      // verder weg ligt. Valhalla leest de tijd als lokale tijd op het
      // vertrekpunt.
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
    DateTime? vertrek,
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
          nu: vertrek,
        ),
        cancelToken: annuleer,
      );
      final routes = leesAntwoord(antwoord.data ?? const {});
      // De vertraging door het verkeer van nu; voor later vertrekken zegt die
      // niets.
      final metVerkeer =
          liveVerkeer && profiel == Profiel.auto && vertrek == null;
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

  /// De maximumsnelheid (km/u) en de OSM-way per stuk van [lijn]: element i
  /// hoort bij het stuk van punt i naar i+1; de limiet is null als die onbekend
  /// is. De way is voor wat Valhalla niet leest: een limiet die van het
  /// tijdstip afhangt (zie [SnelheidTijden]). Null als het hele verzoek mislukt.
  Future<List<StukLimiet>?> snelheidsLimieten(
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
              'edge.way_id',
              'edge.begin_shape_index',
              'edge.end_shape_index',
            ],
            'action': 'include',
          },
        },
        cancelToken: annuleer,
      );
      final perStuk = List<StukLimiet>.filled(punten.length - 1, (
        limiet: null,
        way: null,
      ));
      for (final edge in (antwoord.data?['edges'] as List? ?? const [])) {
        if (edge is! Map) continue;
        final limiet = edge['speed_limit'], way = edge['way_id'];
        final begin = edge['begin_shape_index'], eind = edge['end_shape_index'];
        if (begin is! num || eind is! num) continue;
        // Onbekend is 0 of ontbreekt; "unlimited" (Duitse snelweg) is een tekst.
        final stuk = (
          limiet: limiet is num && limiet > 0 ? limiet.round() : null,
          way: way is num ? way.toInt() : null,
        );
        if (stuk.limiet == null && stuk.way == null) continue;
        for (
          var i = begin.toInt();
          i < eind.toInt() && i < perStuk.length;
          i++
        ) {
          perStuk[i] = stuk;
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

  /// De rijstroken bij de kruisingen langs [lijn], waar OSM ze kent (en
  /// Valhalla ze dus weet). Alleen het OSRM-formaat geeft ze; `edge_walk`
  /// houdt het precies op deze weg. Null als het verzoek mislukt.
  Future<List<RijstrookAdvies>?> rijstroken(
    List<LatLng> lijn,
    Profiel profiel, {
    CancelToken? annuleer,
  }) async {
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
          'format': 'osrm',
        },
        cancelToken: annuleer,
      );
      return leesRijstroken(antwoord.data ?? const {});
    } on DioException catch (fout) {
      if (CancelToken.isCancel(fout)) rethrow;
      return null;
    }
  }

  /// Uit een OSRM-antwoord: elke kruising met rijstroken, op volgorde.
  static List<RijstrookAdvies> leesRijstroken(Map<String, dynamic> json) {
    final uit = <RijstrookAdvies>[];
    for (final match in (json['matchings'] as List? ?? const [])) {
      for (final leg in ((match as Map)['legs'] as List? ?? const [])) {
        for (final stap in ((leg as Map)['steps'] as List? ?? const [])) {
          for (final kruising
              in ((stap as Map)['intersections'] as List? ?? const [])) {
            final plek = (kruising as Map)['location'];
            final stroken = kruising['lanes'];
            if (plek is! List || plek.length < 2 || stroken is! List) continue;
            uit.add((
              plek: LatLng(
                (plek[1] as num).toDouble(),
                (plek[0] as num).toDouble(),
              ),
              stroken: [
                for (final strook in stroken.cast<Map>())
                  Rijstrook(
                    richtingen: [
                      for (final r
                          in (strook['indications'] as List? ?? const []))
                        r as String,
                    ],
                    goed: strook['valid'] == true,
                    gebruik: strook['valid_indication'] as String?,
                  ),
              ],
            ));
          }
        }
      }
    }
    return uit;
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
