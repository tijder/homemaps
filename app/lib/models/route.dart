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
    this.rotondeAfslag,
    this.rotondeHoek,
    this.bord,
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

  /// Bij een rotonde (26 op, 27 af): de hoeveelste afslag, en de hoek van de
  /// uitrit ten opzichte van waar je erop reed (0 = rechtdoor, 90 = rechts,
  /// 270 = links), met de klok mee.
  final int? rotondeAfslag;
  final double? rotondeHoek;

  /// Wat er op de bewegwijzering staat (afritnummer, wegnummers, richtingen).
  final Bord? bord;

  bool get isRotonde => type == 26 || type == 27;

  /// Op- of afrit, splitsing of invoegen: waar de bewegwijzering telt.
  bool get isWegwijzing =>
      (type >= 17 && type <= 25) || type == 37 || type == 38;

  /// Het bord bij een op- of afrit, splitsing of invoegstrook. Staat er geen
  /// bord in de route, dan het wegnummer waar je op komt ("A27"), zoals ook
  /// Google en Apple Maps doen.
  Bord? get wegwijzer {
    if (!isWegwijzing) return null;
    if (bord != null) return bord;
    final weg = hoofdnummer(straten);
    return weg == null ? null : Bord(wegen: [weg]);
  }

  /// Bestemming (4) of een via-punt onderweg (ook 4, of 5/6 rechts/links).
  bool get isBestemming => type >= 4 && type <= 6;
}

/// Rotonde op (26) en af (27) horen bij elkaar: de afslag staat bij de 26, de
/// richting waarin je eraf gaat bij de 27. Beide krijgen hetzelfde.
({int? afslag, double hoek})? _rotonde(List<Map<String, dynamic>> ruw, int i) {
  final type = ruw[i]['type'];
  int op, af;
  if (type == 26) {
    op = i;
    af = i + 1;
    while (af < ruw.length && ruw[af]['type'] != 27) {
      af++;
    }
    if (af == ruw.length) return null;
  } else if (type == 27) {
    af = i;
    op = i - 1;
    while (op >= 0 && ruw[op]['type'] != 26) {
      op--;
    }
    if (op < 0) return null;
  } else {
    return null;
  }
  final voor = ruw[op]['bearing_before'], na = ruw[af]['bearing_after'];
  if (voor is! num || na is! num) return null;
  return (
    afslag: (ruw[op]['roundabout_exit_count'] as num?)?.toInt(),
    hoek: (na - voor + 360) % 360.0,
  );
}

/// Een wegnummer ("A27", "N228", "S100", "E 30"), geen straatnaam.
bool isWegnummer(String naam) => RegExp(r'^[ANSE] ?\d+$').hasMatch(naam);

/// Het wegnummer dat op de borden staat: een A-, N- of S-weg eerst, een
/// E-nummer alleen als er niets anders is. Null als er geen nummer bij is.
String? hoofdnummer(List<String> namen) =>
    namen.where((n) => isWegnummer(n) && !n.startsWith('E')).firstOrNull ??
    namen.where(isWegnummer).firstOrNull;

/// De bewegwijzering bij een manoeuvre, zoals Valhalla die in `sign` geeft.
class Bord {
  const Bord({
    this.afrit,
    this.wegen = const [],
    this.richtingen = const [],
    this.naam,
  });

  /// Het afritnummer ("15").
  final String? afrit;

  /// Wegnummers ("A12", "N228").
  final List<String> wegen;

  /// Plaatsen ("Utrecht", "Amersfoort").
  final List<String> richtingen;

  /// De naam van een knooppunt of afrit ("Knooppunt Lunetten").
  final String? naam;

  /// Null als er niets op staat.
  static Bord? vanValhalla(Object? sign) {
    if (sign is! Map) return null;
    List<String> teksten(String sleutel) {
      final uit = <String>[];
      for (final e in (sign[sleutel] as List? ?? const [])) {
        final tekst = e is Map ? e['text'] : null;
        if (tekst is String && tekst.isNotEmpty && !uit.contains(tekst)) {
          uit.add(tekst);
        }
      }
      return uit;
    }

    // De borden bij de afrit gaan voor; anders die boven de doorgaande weg
    // (OSM `destination` op de hoofdrijbaan) of de naam van het knooppunt.
    List<String> eerst(String afrit, String gids) {
      final uit = teksten(afrit);
      return uit.isNotEmpty ? uit : teksten(gids);
    }

    final afrit = teksten('exit_number_elements');
    final naam = eerst('exit_name_elements', 'junction_name_elements');
    final bord = Bord(
      afrit: afrit.firstOrNull,
      wegen: eerst('exit_branch_elements', 'guide_branch_elements'),
      richtingen: eerst('exit_toward_elements', 'guide_toward_elements'),
      naam: naam.firstOrNull,
    );
    return bord.afrit == null &&
            bord.wegen.isEmpty &&
            bord.richtingen.isEmpty &&
            bord.naam == null
        ? null
        : bord;
  }
}

/// Eén rijstrook bij een kruising, van links naar rechts geteld.
class Rijstrook {
  const Rijstrook({required this.richtingen, required this.goed, this.gebruik});

  /// Zoals OSRM ze noemt: "straight", "slight right", "left", "uturn", ...
  final List<String> richtingen;

  /// Op deze strook blijf je op de route.
  final bool goed;

  /// Welke van [richtingen] je hier neemt, als de strook er meer heeft.
  final String? gebruik;
}

/// Rijstroken bij een kruising op de route.
typedef RijstrookAdvies = ({LatLng plek, List<Rijstrook> stroken});

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
      final ruw = (leg['maneuvers'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final (i, m) in ruw.indexed) {
        final rotonde = _rotonde(ruw, i);
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
            rotondeAfslag: rotonde?.afslag,
            rotondeHoek: rotonde?.hoek,
            bord: Bord.vanValhalla(m['sign']),
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
