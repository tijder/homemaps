import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/route.dart';
import '../utils/afstand.dart';

/// Bij deze manoeuvres staat er een pijl op de kaart: afslaan, op- en afritten,
/// links of rechts aanhouden, invoegen en rotondes. Niet bij rechtdoor, start,
/// bestemming of een veerpont.
bool heeftAfslagPijl(Manoeuvre m) =>
    (m.type >= 9 && m.type <= 21) ||
    (m.type >= 23 && m.type <= 27) ||
    m.type == 37 ||
    m.type == 38;

/// Het stukje route rond manoeuvre [index] voor de pijl op de kaart, zoals bij
/// Google en Apple Maps: [voor] meter ervoor tot [na] meter erna. Bij een
/// rotonde (26) loopt hij door tot voorbij de uitrit (27). Null als er bij deze
/// manoeuvre geen pijl hoort.
List<LatLng>? afslagPijl(
  RouteOptie route,
  int index, {
  double voor = 40,
  double na = 30,
}) {
  final m = route.manoeuvres;
  if (index <= 0 || index >= m.length || !heeftAfslagPijl(m[index])) {
    return null;
  }
  final punten = route.punten;
  if (punten.length < 2) return null;
  final tot = <double>[0];
  for (var i = 1; i < punten.length; i++) {
    tot.add(tot.last + meters(punten[i - 1], punten[i]));
  }
  double langs(int vormIndex) => tot[vormIndex.clamp(0, tot.length - 1)];

  var eind = m[index];
  if (eind.type == 26) {
    final af = m.indexWhere((x) => x.type == 27, index + 1);
    if (af > 0) eind = m[af];
  }
  return stukLangs(
    punten,
    tot,
    langs(m[index].vormIndex) - voor,
    langs(eind.vormIndex) + na,
  );
}

/// Het deel van [punten] tussen [van] en [totM] meter langs de lijn, met de
/// uiteinden precies op die afstand. [tot] is de afstand tot elk punt.
List<LatLng> stukLangs(
  List<LatLng> punten,
  List<double> tot,
  double van,
  double totM,
) {
  van = van.clamp(0, tot.last);
  totM = totM.clamp(van, tot.last);
  LatLng op(double afstand) {
    var i = 1;
    while (i < tot.length - 1 && tot[i] < afstand) {
      i++;
    }
    final stuk = tot[i] - tot[i - 1];
    final t = stuk == 0 ? 0.0 : (afstand - tot[i - 1]) / stuk;
    final a = punten[i - 1], b = punten[i];
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  return [
    op(van),
    for (var i = 0; i < punten.length; i++)
      if (tot[i] > van && tot[i] < totM) punten[i],
    op(totM),
  ];
}
