import 'package:maplibre_gl/maplibre_gl.dart';

import '../utils/polyline.dart';

class Manoeuvre {
  const Manoeuvre({
    required this.instructie,
    required this.type,
    required this.meters,
    required this.seconden,
    required this.vormIndex,
  });

  final String instructie;

  /// Valhalla's manoeuvretype (1 = start, 4 = bestemming, 10 = rechtsaf, ...).
  final int type;
  final double meters;
  final double seconden;

  /// Waar in [RouteOptie.punten] deze manoeuvre begint.
  final int vormIndex;
}

class RouteOptie {
  const RouteOptie({
    required this.meters,
    required this.seconden,
    required this.punten,
    required this.manoeuvres,
    required this.hoogtes,
    required this.hoogteInterval,
    required this.heeftTol,
    required this.heeftVeer,
  });

  final double meters;
  final double seconden;
  final List<LatLng> punten;
  final List<Manoeuvre> manoeuvres;

  /// Hoogte in meters, elke [hoogteInterval] meter langs de route. Leeg als de
  /// server geen hoogtedata heeft.
  final List<double> hoogtes;
  final double hoogteInterval;
  final bool heeftTol;
  final bool heeftVeer;

  double get stijging => _som((verschil) => verschil > 0 ? verschil : 0);
  double get daling => _som((verschil) => verschil < 0 ? -verschil : 0);

  double _som(double Function(double) deel) {
    var totaal = 0.0;
    for (var i = 1; i < hoogtes.length; i++) {
      totaal += deel(hoogtes[i] - hoogtes[i - 1]);
    }
    return totaal;
  }

  /// Eén `trip` uit het antwoord van Valhalla. Een route met via-punten heeft
  /// meerdere legs; die worden hier aan elkaar geregen.
  factory RouteOptie.vanValhalla(
    Map<String, dynamic> trip, {
    required double hoogteInterval,
  }) {
    final samenvatting = (trip['summary'] as Map).cast<String, dynamic>();
    final punten = <LatLng>[];
    final manoeuvres = <Manoeuvre>[];
    final hoogtes = <double>[];
    for (final leg in (trip['legs'] as List).cast<Map<String, dynamic>>()) {
      final verschuiving = punten.length;
      punten.addAll(decodeerPolyline(leg['shape'] as String));
      for (final m
          in (leg['maneuvers'] as List? ?? const [])
              .cast<Map<String, dynamic>>()) {
        manoeuvres.add(
          Manoeuvre(
            instructie: m['instruction'] as String? ?? '',
            type: (m['type'] as num?)?.toInt() ?? 0,
            meters: ((m['length'] as num?)?.toDouble() ?? 0) * 1000,
            seconden: (m['time'] as num?)?.toDouble() ?? 0,
            vormIndex:
                verschuiving + ((m['begin_shape_index'] as num?)?.toInt() ?? 0),
          ),
        );
      }
      hoogtes.addAll(
        (leg['elevation'] as List? ?? const []).map(
          (h) => (h as num).toDouble(),
        ),
      );
    }
    return RouteOptie(
      meters: (samenvatting['length'] as num).toDouble() * 1000,
      seconden: (samenvatting['time'] as num).toDouble(),
      punten: punten,
      manoeuvres: manoeuvres,
      hoogtes: hoogtes,
      hoogteInterval: hoogteInterval,
      heeftTol: samenvatting['has_toll'] == true,
      heeftVeer: samenvatting['has_ferry'] == true,
    );
  }
}
