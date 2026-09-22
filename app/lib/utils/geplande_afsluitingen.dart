import 'dart:math';

import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/route.dart';

/// Een geplande afsluiting die op een route ligt, met het venster waarin hij
/// je reis raakt.
typedef AfsluitingOpRoute = ({DateTime van, DateTime? tot});

/// Welke geplande afsluitingen uit [laag] op [route] liggen terwijl je hem
/// rijdt (van [vertrek] tot aankomst, met een uur speling). Valhalla kan niet
/// om een afsluiting in de toekomst heen rekenen; dit is de waarschuwing.
///
/// "Op de route": minstens twee van de drie punten van de afsluiting (begin,
/// midden, eind) liggen binnen 20 m van de routelijn. Eerst een ruwe
/// begrenzing om de route, anders wordt het voor duizenden afsluitingen traag.
List<AfsluitingOpRoute> afsluitingenOpRoute(
  RouteOptie route,
  Map<String, dynamic> laag,
  DateTime vertrek,
) {
  if (route.punten.length < 2) return const [];
  final eind = vertrek.add(Duration(seconds: route.seconden.round() + 3600));
  var zuid = 90.0, noord = -90.0, west = 180.0, oost = -180.0;
  for (final p in route.punten) {
    zuid = min(zuid, p.latitude);
    noord = max(noord, p.latitude);
    west = min(west, p.longitude);
    oost = max(oost, p.longitude);
  }
  const marge = 0.001; // ~100 m
  bool binnen(LatLng p) =>
      p.latitude >= zuid - marge &&
      p.latitude <= noord + marge &&
      p.longitude >= west - marge &&
      p.longitude <= oost + marge;

  final uit = <AfsluitingOpRoute>[];
  for (final feature in (laag['features'] as List? ?? const [])) {
    if (feature is! Map) continue;
    final eigen = (feature['properties'] as Map?) ?? const {};
    final venster = _raakt(eigen['vensters'], vertrek, eind);
    if (venster == null) continue;
    final lijn = _lijn(feature['geometry']);
    if (lijn.length < 2) continue;
    final toets = [lijn.first, lijn[lijn.length ~/ 2], lijn.last];
    if (!toets.any(binnen)) continue;
    final raak = toets.where((p) => _afstandTotLijn(p, route.punten) < 20);
    if (raak.length >= 2) uit.add(venster);
  }
  uit.sort((a, b) => a.van.compareTo(b.van));
  return uit;
}

AfsluitingOpRoute? _raakt(Object? vensters, DateTime van, DateTime tot) {
  if (vensters is! List) return null;
  for (final venster in vensters) {
    if (venster is! List || venster.isEmpty) continue;
    final begin = DateTime.tryParse(venster[0] as String? ?? '');
    final einde = venster.length > 1 && venster[1] is String
        ? DateTime.tryParse(venster[1] as String)
        : null;
    if (begin == null) continue;
    if (begin.isAfter(tot) || (einde != null && einde.isBefore(van))) continue;
    return (van: begin, tot: einde);
  }
  return null;
}

List<LatLng> _lijn(Object? geometrie) {
  if (geometrie is! Map) return const [];
  LatLng punt(Object? c) {
    final l = (c as List).cast<num>();
    return LatLng(l[1].toDouble(), l[0].toDouble());
  }

  return switch (geometrie['type']) {
    'LineString' => [for (final c in geometrie['coordinates'] as List) punt(c)],
    'MultiLineString' => [
      for (final deel in geometrie['coordinates'] as List)
        for (final c in deel as List) punt(c),
    ],
    _ => const [],
  };
}

/// Meters van [p] tot de dichtstbijzijnde plek op [lijn] (platte projectie).
double _afstandTotLijn(LatLng p, List<LatLng> lijn) {
  final kos = cos(p.latitude * pi / 180);
  var beste = double.infinity;
  for (var i = 0; i < lijn.length - 1; i++) {
    final ax = (lijn[i].longitude - p.longitude) * kos * 111320;
    final ay = (lijn[i].latitude - p.latitude) * 110574;
    final bx = (lijn[i + 1].longitude - p.longitude) * kos * 111320;
    final by = (lijn[i + 1].latitude - p.latitude) * 110574;
    final dx = bx - ax, dy = by - ay;
    final kwadraat = dx * dx + dy * dy;
    final t = kwadraat == 0
        ? 0.0
        : ((-ax * dx - ay * dy) / kwadraat).clamp(0.0, 1.0);
    final x = ax + t * dx, y = ay + t * dy;
    beste = min(beste, x * x + y * y);
  }
  return sqrt(beste);
}
