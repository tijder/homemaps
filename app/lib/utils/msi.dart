import 'dart:math';

import 'package:maplibre_gl/maplibre_gl.dart';

import '../navigatie/volger.dart';

/// Een portaal met matrixborden op de route: hoe ver langs de route, en per
/// strook (van links naar rechts) wat erop staat. Codes zoals de importer ze
/// geeft: "70" (advies), "70r" (verplicht, rode ring), "x" (rijstrook dicht),
/// "<" / ">" (invoegen naar links/rechts), "open", "einde" of "" (leeg).
typedef Portaal = ({double langs, List<String> stroken});

/// De portalen uit [laag] (`soort: msi`) die boven jouw rijbaan hangen: binnen
/// [maxAfstand] van de route, en in dezelfde richting (de overkant van de
/// snelweg ligt er ook vlakbij). Hangen er twee op dezelfde plek langs de
/// route (hoofdbaan en parallelbaan), dan telt het dichtstbij. Op volgorde
/// langs de route.
///
/// Het punt van een portaal ligt meestal op de lijn van de rijbaan (0-2 m),
/// soms tot ~25 m ernaast.
List<Portaal> portalenOpRoute(
  RouteVolger volger,
  Map<String, dynamic>? laag, {
  double maxAfstand = 35,
  double maxHoek = 45,
}) {
  final route = volger.route.punten;
  if (laag == null || route.length < 2) return const [];
  var zuid = 90.0, noord = -90.0, west = 180.0, oost = -180.0;
  for (final p in route) {
    zuid = min(zuid, p.latitude);
    noord = max(noord, p.latitude);
    west = min(west, p.longitude);
    oost = max(oost, p.longitude);
  }
  const marge = 0.001; // ~100 m
  final gevonden = <({Portaal portaal, double afstand})>[];
  for (final feature in (laag['features'] as List? ?? const [])) {
    if (feature is! Map) continue;
    final eigen = feature['properties'];
    final geometrie = feature['geometry'];
    if (eigen is! Map ||
        eigen['soort'] != 'msi' ||
        geometrie is! Map ||
        geometrie['type'] != 'Point') {
      continue;
    }
    final c = (geometrie['coordinates'] as List).cast<num>();
    final punt = LatLng(c[1].toDouble(), c[0].toDouble());
    if (punt.latitude < zuid - marge ||
        punt.latitude > noord + marge ||
        punt.longitude < west - marge ||
        punt.longitude > oost + marge) {
      continue;
    }
    final plek = volger.plaatsOp(punt);
    final koers = eigen['koers'];
    if (plek.afstand > maxAfstand ||
        koers is! num ||
        hoekVerschil(koers.toDouble(), plek.koers) > maxHoek) {
      continue;
    }
    gevonden.add((
      portaal: (
        langs: plek.langs,
        stroken: [
          for (final s in (eigen['stroken'] as List? ?? const [])) '$s',
        ],
      ),
      afstand: plek.afstand,
    ));
  }
  gevonden.sort((a, b) => a.portaal.langs.compareTo(b.portaal.langs));
  final uit = <({Portaal portaal, double afstand})>[];
  for (final g in gevonden) {
    if (uit.isNotEmpty && g.portaal.langs - uit.last.portaal.langs < 60) {
      if (g.afstand < uit.last.afstand) uit[uit.length - 1] = g;
      continue;
    }
    uit.add(g);
  }
  return [for (final g in uit) g.portaal];
}

/// De verplichte snelheid (rode ring) van de matrixborden waar je nu onder
/// rijdt: die van het laatst gepasseerde portaal, tot [geldigTot] meter erna.
/// Een snelheid boven de weg geldt tot het volgende portaal; staat daar niets
/// (of "einde"), dan houdt hij op. Verschilt hij per strook, dan de laagste.
/// Null als er geen geldt. Een advies (zonder rode ring) is geen limiet.
int? msiLimiet(
  List<Portaal> portalen,
  double langs, {
  double geldigTot = 3000,
}) {
  Portaal? laatste;
  for (final portaal in portalen) {
    if (portaal.langs > langs + 5) break;
    laatste = portaal;
  }
  if (laatste == null || langs - laatste.langs > geldigTot) return null;
  int? laagste;
  for (final strook in laatste.stroken) {
    if (!strook.endsWith('r')) continue;
    final kmu = int.tryParse(strook.substring(0, strook.length - 1));
    if (kmu != null && (laagste == null || kmu < laagste)) laagste = kmu;
  }
  return laagste;
}

/// Het eerstvolgende portaal binnen [vooruit] meter waar iets op staat, en hoe
/// ver het nog is.
({double over, List<String> stroken})? volgendPortaal(
  List<Portaal> portalen,
  double langs, {
  double vooruit = 1500,
}) {
  for (final portaal in portalen) {
    if (portaal.langs <= langs + 5) continue;
    if (portaal.langs - langs > vooruit) return null;
    if (portaal.stroken.any((s) => s.isNotEmpty)) {
      return (over: portaal.langs - langs, stroken: portaal.stroken);
    }
    // Een leeg portaal: de beperkingen houden daar op; wat erna komt telt
    // pas als je er langs bent.
    return null;
  }
  return null;
}
