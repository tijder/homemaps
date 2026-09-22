import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/plaats.dart';
import '../models/profiel.dart';
import '../utils/afstand.dart';
import '../utils/mvt.dart';

/// Wat je langs de route kunt zoeken, met de klassen uit OpenMapTiles' laag
/// `poi` (class/subclass).
enum Categorie {
  tanken,
  laden,
  supermarkt,
  eten;

  bool past(Map<String, Object?> poi) => switch (this) {
    tanken => poi['class'] == 'fuel' && poi['subclass'] == 'fuel',
    laden => poi['subclass'] == 'charging_station',
    supermarkt => poi['subclass'] == 'supermarket',
    eten => const {'restaurant', 'fast_food', 'cafe'}.contains(poi['class']),
  };
}

class Treffer {
  const Treffer(this.plaats, this.afstandTotRoute, this.omwegSeconden);

  final Plaats plaats;
  final double afstandTotRoute;

  /// Hoeveel langer de reis wordt met deze stop; null als Valhalla het niet
  /// kon zeggen.
  final double? omwegSeconden;
}

/// Zoekt in de eigen vectortegels naar plekken vlak langs een route, en laat
/// Valhalla uitrekenen hoeveel omweg elke stop kost.
class LangsRouteService {
  LangsRouteService(this._dio, this.tilesUrl, this.valhallaUrl);

  final Dio _dio;
  final String tilesUrl;
  final String valhallaUrl;

  static const _zoom = 14;

  /// [lijn]: de route vanaf waar je nu bent. Alleen de eerste [maxLengte]
  /// meter telt: een tankstation 200 km verderop helpt nu niet.
  Future<List<Treffer>> zoek(
    List<LatLng> lijn,
    Categorie categorie, {
    required Profiel profiel,
    required String naamZonderNaam,
    double maxAfstand = 1000,
    double maxLengte = 80000,
    int maxKandidaten = 20,
    CancelToken? annuleer,
  }) async {
    final stuk = _begin(lijn, maxLengte);
    if (stuk.length < 2) return const [];

    // Tegels in een strook van ~700 m om de route.
    final tegels = <(int, int)>{};
    for (final punt in _elke(stuk, 400)) {
      final marge = 700 / 111320;
      final lonMarge = marge / cos(punt.latitude * pi / 180);
      final (x0, y0) = _tegel(punt.latitude + marge, punt.longitude - lonMarge);
      final (x1, y1) = _tegel(punt.latitude - marge, punt.longitude + lonMarge);
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          tegels.add((x, y));
        }
      }
      if (tegels.length > 150) break;
    }

    final gezien = <String>{};
    final kandidaten = <(TegelPunt, double)>[];
    final lijst = tegels.toList();
    // In groepjes van acht tegelijk: genoeg om snel te zijn, niet zoveel dat de
    // tileserver het merkt.
    for (var i = 0; i < lijst.length; i += 8) {
      final groep = lijst.skip(i).take(8);
      final resultaten = await Future.wait([
        for (final (x, y) in groep) _poi(x, y, annuleer),
      ]);
      for (final poi in resultaten.expand((r) => r)) {
        if (!categorie.past(poi.eigenschappen)) continue;
        // Een punt vlak bij de rand staat in meer tegels.
        final sleutel =
            '${poi.eigenschappen['name']}@${poi.punt.latitude.toStringAsFixed(4)},'
            '${poi.punt.longitude.toStringAsFixed(4)}';
        if (!gezien.add(sleutel)) continue;
        final afstand = metersTotLijn(poi.punt, stuk);
        if (afstand <= maxAfstand) kandidaten.add((poi, afstand));
      }
    }
    kandidaten.sort((a, b) => a.$2.compareTo(b.$2));
    final beste = kandidaten.take(maxKandidaten).toList();
    if (beste.isEmpty) return const [];

    final omwegen = await _omwegen(
      stuk.first,
      lijn.last,
      [for (final (poi, _) in beste) poi.punt],
      profiel,
      annuleer,
    );
    final uit = [
      for (final (i, (poi, afstand)) in beste.indexed)
        Treffer(
          Plaats(
            naam:
                (poi.eigenschappen['name'] as String?)?.trim().isNotEmpty ==
                    true
                ? poi.eigenschappen['name'] as String
                : naamZonderNaam,
            punt: poi.punt,
          ),
          afstand,
          omwegen?[i],
        ),
    ];
    uit.sort(
      (a, b) => (a.omwegSeconden ?? a.afstandTotRoute).compareTo(
        b.omwegSeconden ?? b.afstandTotRoute,
      ),
    );
    return uit;
  }

  Future<List<TegelPunt>> _poi(int x, int y, CancelToken? annuleer) async {
    try {
      final antwoord = await _dio.get<List<int>>(
        '$tilesUrl/data/v3/$_zoom/$x/$y.pbf',
        options: Options(responseType: ResponseType.bytes),
        cancelToken: annuleer,
      );
      final data = antwoord.data;
      // Leeg (zee) of toch nog ingepakt: dan niets. De browser en Dart pakken
      // gzip met Content-Encoding zelf uit.
      if (data == null ||
          data.length < 2 ||
          (data[0] == 0x1f && data[1] == 0x8b)) {
        return const [];
      }
      return puntenUitTegel(
        Uint8List.fromList(data),
        laag: 'poi',
        z: _zoom,
        x: x,
        y: y,
      );
    } on DioException catch (fout) {
      if (CancelToken.isCancel(fout)) rethrow;
      return const [];
    } on FormatException {
      return const [];
    }
  }

  /// Per kandidaat: (van → stop) + (stop → naar) − (van → naar), met één
  /// matrixverzoek.
  Future<List<double?>?> _omwegen(
    LatLng van,
    LatLng naar,
    List<LatLng> stops,
    Profiel profiel,
    CancelToken? annuleer,
  ) async {
    Map<String, double> plek(LatLng p) => {
      'lat': p.latitude,
      'lon': p.longitude,
    };
    try {
      final antwoord = await _dio.post<Map<String, dynamic>>(
        '$valhallaUrl/sources_to_targets',
        data: {
          'sources': [plek(van), for (final s in stops) plek(s)],
          'targets': [for (final s in stops) plek(s), plek(naar)],
          'costing': profiel.costing,
        },
        cancelToken: annuleer,
      );
      final matrix = antwoord.data?['sources_to_targets'] as List?;
      if (matrix == null) return null;
      double? tijd(int bron, int doel) {
        final waarde = ((matrix[bron] as List)[doel] as Map)['time'];
        return waarde is num ? waarde.toDouble() : null;
      }

      final direct = tijd(0, stops.length);
      if (direct == null) return null;
      return [
        for (var i = 0; i < stops.length; i++)
          switch ((tijd(0, i), tijd(i + 1, stops.length))) {
            (final heen?, final terug?) => max(0, heen + terug - direct),
            _ => null,
          },
      ];
    } on DioException catch (fout) {
      if (CancelToken.isCancel(fout)) rethrow;
      return null;
    }
  }

  static (int, int) _tegel(double lat, double lon) {
    final n = pow(2, _zoom);
    final x = ((lon + 180) / 360 * n).floor();
    final r = lat * pi / 180;
    final y = ((1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * n).floor();
    return (x, y);
  }

  static List<LatLng> _begin(List<LatLng> lijn, double lengte) {
    final uit = <LatLng>[];
    var afgelegd = 0.0;
    for (final (i, p) in lijn.indexed) {
      if (i > 0) afgelegd += meters(lijn[i - 1], p);
      uit.add(p);
      if (afgelegd > lengte) break;
    }
    return uit;
  }

  /// Punten om de [stap] meter langs [lijn] (ook midden op lange rechte
  /// stukken), het laatste erbij.
  static Iterable<LatLng> _elke(List<LatLng> lijn, double stap) sync* {
    yield lijn.first;
    var tot = stap;
    for (var i = 1; i < lijn.length; i++) {
      final a = lijn[i - 1], b = lijn[i];
      final stuk = meters(a, b);
      var op = tot;
      while (op <= stuk) {
        final t = op / stuk;
        yield LatLng(
          a.latitude + t * (b.latitude - a.latitude),
          a.longitude + t * (b.longitude - a.longitude),
        );
        op += stap;
      }
      tot = op - stuk;
    }
    yield lijn.last;
  }
}
