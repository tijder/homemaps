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
          },
      ],
      'costing': profiel.costing,
      if (opties.isNotEmpty) 'costing_options': {profiel.costing: opties},
      'units': 'kilometers',
      'language': taal,
      'elevation_interval': hoogteInterval,
      // Valhalla geeft alleen alternatieven tussen precies twee punten.
      if (punten.length == 2) 'alternates': 2,
      // Live verkeer telt alleen bij "vertrek nu", en alleen voor de auto.
      if (liveVerkeer && profiel == Profiel.auto) 'date_time': {'type': 0},
    };
  }

  Future<List<RouteOptie>> route(
    List<LatLng> punten,
    Profiel profiel, {
    required String taal,
    bool liveVerkeer = true,
    bool vermijdSnelwegen = false,
    bool vermijdTol = false,
    bool vermijdVeren = false,
    CancelToken? annuleer,
  }) async {
    Future<List<RouteOptie>> vraag({required bool live}) async {
      final antwoord = await _dio.post<Map<String, dynamic>>(
        '$basis/route',
        data: verzoek(
          punten,
          profiel,
          taal: taal,
          liveVerkeer: live,
          vermijdSnelwegen: vermijdSnelwegen,
          vermijdTol: vermijdTol,
          vermijdVeren: vermijdVeren,
        ),
        cancelToken: annuleer,
      );
      return leesAntwoord(antwoord.data ?? const {});
    }

    try {
      final metVertrektijd =
          liveVerkeer && profiel == Profiel.auto && punten.length == 2;
      if (!metVertrektijd) return await vraag(live: liveVerkeer);
      // Valhalla geeft bij een vertrektijd geen alternatieven: die komen alleen
      // uit zijn tweerichtingszoeker, en die rekent zonder tijd. Daarom twee
      // verzoeken tegelijk -- de route van nu met live verkeer, en de
      // alternatieven zonder -- en daarna samenvoegen.
      final (nu, zonderTijd) = await (
        vraag(live: true),
        vraag(live: false),
      ).wait;
      return voegSamen(nu, zonderTijd);
    } on ParallelWaitError<dynamic, dynamic> catch (fout) {
      // Het eerste echte probleem van de twee; de afhandeling hieronder past erop.
      final (eerste, tweede) = fout.errors as (AsyncError?, AsyncError?);
      final oorzaak = (eerste ?? tweede)!.error;
      if (oorzaak is DioException) {
        if (CancelToken.isCancel(oorzaak)) throw oorzaak;
        throw _routeFout(oorzaak);
      }
      throw oorzaak;
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

  /// De route met live verkeer voorop, daarna de alternatieven uit het verzoek
  /// zonder vertrektijd -- behalve die welke dezelfde weg zijn als de eerste. De
  /// hoofdroute van het tweede verzoek doet ook mee: met file kan juist die het
  /// alternatief zijn.
  static List<RouteOptie> voegSamen(
    List<RouteOptie> nu,
    List<RouteOptie> zonderTijd,
  ) {
    final uit = [...nu];
    for (final kandidaat in zonderTijd) {
      final dubbel = uit.any(
        (route) => (route.meters - kandidaat.meters).abs() < 50,
      );
      if (!dubbel) uit.add(kandidaat);
    }
    return uit.take(3).toList();
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
