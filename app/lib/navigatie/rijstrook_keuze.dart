import 'dart:math';

import '../models/route.dart';

/// De rijstroken die in de kop staan, hoe ver die kruising nog is, en of het
/// de kruising van de manoeuvre in de kop is (anders ligt hij ervoor).
typedef RijstrookKeuze = ({
  double over,
  List<Rijstrook> stroken,
  bool bijManoeuvre,
});

/// Zoveel seconden vóór de manoeuvre komen de rijstroken in beeld...
const rijstrookSeconden = 35.0;

/// ...maar niet eerder dan zoveel meter ervoor...
const rijstrookMax = 1500.0;

/// ...en niet later dan zoveel meter ervoor.
const rijstrookMin = 300.0;

/// Een kruising vóór de manoeuvre (een splitsing, een strook die ophoudt)
/// staat pas zo kort van tevoren in beeld, met zijn eigen afstand erbij.
const rijstrookTussen = 400.0;

/// Zo dicht bij de manoeuvre hoort een kruising bij de manoeuvre zelf.
const _bijMarge = 50.0;

/// Welke rijstroken er in de kop horen, of null.
///
/// Zoals bij Google of Apple Maps: de stroken van de afslag in de kop, pas
/// vlak ervoor. Een kruising daarvoor waar het ook uitmaakt welke strook je
/// neemt, gaat voor zodra hij dichtbij is. Die krijgt zijn afstand erbij, zodat
/// hij niet lijkt op de afslag in de kop.
///
/// [kruisingen] op volgorde langs de route; [langs] is waar je bent en
/// [manoeuvre] waar de volgende manoeuvre ligt, allebei langs de route;
/// [snelheid] in m/s.
RijstrookKeuze? kiesRijstroken(
  List<({double langs, List<Rijstrook> stroken})> kruisingen, {
  required double langs,
  required double manoeuvre,
  double? snelheid,
}) {
  final vooruit = snelheid == null
      ? rijstrookMax
      : (snelheid * rijstrookSeconden).clamp(rijstrookMin, rijstrookMax);
  ({double langs, List<Rijstrook> stroken})? tussen, bij;
  for (final kruising in kruisingen) {
    if (kruising.langs < langs) continue;
    if (kruising.langs > manoeuvre + 10) break;
    // Eén strook, of elke strook goed: dan valt er niets te kiezen.
    if (kruising.stroken.length < 2 || kruising.stroken.every((s) => s.goed)) {
      continue;
    }
    if (kruising.langs >= manoeuvre - _bijMarge) {
      bij = kruising;
    } else {
      tussen ??= kruising;
    }
  }
  if (tussen != null && tussen.langs - langs <= min(vooruit, rijstrookTussen)) {
    return (
      over: tussen.langs - langs,
      stroken: tussen.stroken,
      bijManoeuvre: false,
    );
  }
  if (bij != null && manoeuvre - langs <= vooruit) {
    return (over: bij.langs - langs, stroken: bij.stroken, bijManoeuvre: true);
  }
  return null;
}
