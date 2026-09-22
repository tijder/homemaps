import 'package:maplibre_gl/maplibre_gl.dart';

import '../utils/polyline.dart';

class Manoeuvre {
  const Manoeuvre({
    required this.instructie,
    required this.type,
    required this.meters,
    required this.seconden,
    required this.vormIndex,
    int? eindVormIndex,
    this.straten = const [],
    this.stemVooraf,
    this.stemVlakVoor,
    this.stemNa,
    this.metVolgende = false,
  }) : eindVormIndex = eindVormIndex ?? vormIndex;

  final String instructie;

  /// Valhalla's manoeuvretype (1 = start, 4 = bestemming, 10 = rechtsaf, ...).
  final int type;
  final double meters;
  final double seconden;

  /// Waar in [RouteOptie.punten] deze manoeuvre begint en eindigt.
  final int vormIndex;
  final int eindVormIndex;

  /// De straat (of wegnummers) waar je na de manoeuvre op rijdt.
  final List<String> straten;

  /// Valhalla's gesproken zinnen, al in de taal van het verzoek: ruim van
  /// tevoren ("Links afslaan naar X."), vlak ervoor (met "Daarna ..." als de
  /// volgende dichtbij is) en erna ("400 meter doorgaan.").
  final String? stemVooraf;
  final String? stemVlakVoor;
  final String? stemNa;

  /// [stemVlakVoor] noemt de manoeuvre hierna al ("Daarna, over 400 meter, ...").
  final bool metVolgende;

  /// Bestemming (4) of een via-punt onderweg (ook 4, of 5/6 rechts/links).
  bool get isBestemming => type >= 4 && type <= 6;
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
    this.normaleSeconden,
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

  /// Dezelfde weg zonder het verkeer van nu; null als dat niet bekend is (geen
  /// live verkeer gevraagd, of de server gaf het niet).
  final double? normaleSeconden;

  /// Hoeveel langer het nu duurt door files en drukte; nul als het meevalt.
  double get vertraging => normaleSeconden == null
      ? 0
      : (seconden - normaleSeconden!).clamp(0, double.infinity);

  RouteOptie metNormaleTijd(double? seconden) => RouteOptie(
    meters: meters,
    seconden: this.seconden,
    punten: punten,
    manoeuvres: manoeuvres,
    hoogtes: hoogtes,
    hoogteInterval: hoogteInterval,
    heeftTol: heeftTol,
    heeftVeer: heeftVeer,
    normaleSeconden: seconden,
  );

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
            eindVormIndex:
                verschuiving + ((m['end_shape_index'] as num?)?.toInt() ?? 0),
            straten: [
              for (final naam in (m['street_names'] as List? ?? const []))
                naam as String,
            ],
            stemVooraf: m['verbal_transition_alert_instruction'] as String?,
            stemVlakVoor: m['verbal_pre_transition_instruction'] as String?,
            stemNa: m['verbal_post_transition_instruction'] as String?,
            metVolgende: m['verbal_multi_cue'] == true,
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
