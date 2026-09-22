import 'dart:math';

import 'package:maplibre_gl/maplibre_gl.dart';

/// De tijdelijke maximumsnelheid (km/u) per stuk van [route]: element i hoort
/// bij het stuk van punt i naar i+1, null waar er geen geldt. Uit de
/// verkeerslaag (`soort: snelheid`, bij werk of een evenement; zie de importer).
///
/// Een stuk valt eronder als zijn midden binnen [maxAfstand] van zo'n lijn ligt
/// en de lijn daar dezelfde kant op loopt (binnen [maxHoek]): de lijn heeft een
/// rijrichting, en de rijbaan aan de overkant van de snelweg ligt ook vlakbij.
/// Liggen er twee over elkaar, dan telt de laagste.
List<int?> tijdelijkeSnelheden(
  List<LatLng> route,
  Map<String, dynamic>? laag, {
  double maxAfstand = 15,
  double maxHoek = 45,
}) {
  final perStuk = List<int?>.filled(max(0, route.length - 1), null);
  if (laag == null || perStuk.isEmpty) return perStuk;
  final rond = _Doos.om(route, 0.001); // ~100 m
  final middens = [
    for (var i = 0; i < route.length - 1; i++)
      LatLng(
        (route[i].latitude + route[i + 1].latitude) / 2,
        (route[i].longitude + route[i + 1].longitude) / 2,
      ),
  ];
  // De middens in vakjes van ~500 m: een beperking is kort, en er liggen er
  // duizenden in het land. Zo kijkt elke alleen naar de stukken in de buurt.
  final vakjes = <int, List<int>>{};
  for (final (i, m) in middens.indexed) {
    (vakjes[_vakje(m.latitude, m.longitude)] ??= []).add(i);
  }
  for (final feature in (laag['features'] as List? ?? const [])) {
    if (feature is! Map) continue;
    final eigen = feature['properties'];
    final kmu = eigen is Map ? eigen['kmu'] : null;
    if (eigen is! Map || eigen['soort'] != 'snelheid' || kmu is! num) {
      continue;
    }
    for (final lijn in _lijnen(feature['geometry'])) {
      if (lijn.length < 2) continue;
      final doos = _Doos.om(lijn, 0.0003); // ~30 m
      if (!doos.raakt(rond)) continue;
      for (final i in doos.vakjes().expand((v) => vakjes[v] ?? const <int>[])) {
        final m = middens[i];
        if (!doos.bevat(m)) continue;
        final plek = _dichtsbij(m, lijn);
        // Voorbij het begin of eind van de lijn: de weg loopt daar door, maar
        // de beperking niet.
        if (plek.afstand > maxAfstand || plek.voorbij) continue;
        final koers = _koers(route[i], route[i + 1], m);
        if (_hoekVerschil(koers, plek.koers) > maxHoek) continue;
        final waarde = kmu.round();
        if (perStuk[i] == null || waarde < perStuk[i]!) perStuk[i] = waarde;
      }
    }
  }
  return perStuk;
}

List<List<LatLng>> _lijnen(Object? geometrie) {
  if (geometrie is! Map) return const [];
  List<LatLng> lijn(Object? coordinaten) => [
    for (final c in (coordinaten as List? ?? const []))
      if (c is List && c.length >= 2)
        LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
  ];
  return switch (geometrie['type']) {
    'LineString' => [lijn(geometrie['coordinates'])],
    'MultiLineString' => [
      for (final deel in (geometrie['coordinates'] as List? ?? const []))
        lijn(deel),
    ],
    _ => const [],
  };
}

class _Doos {
  _Doos(this.zuid, this.noord, this.west, this.oost);

  factory _Doos.om(List<LatLng> punten, double marge) {
    var zuid = 90.0, noord = -90.0, west = 180.0, oost = -180.0;
    for (final p in punten) {
      zuid = min(zuid, p.latitude);
      noord = max(noord, p.latitude);
      west = min(west, p.longitude);
      oost = max(oost, p.longitude);
    }
    return _Doos(zuid - marge, noord + marge, west - marge, oost + marge);
  }

  final double zuid, noord, west, oost;

  bool bevat(LatLng p) =>
      p.latitude >= zuid &&
      p.latitude <= noord &&
      p.longitude >= west &&
      p.longitude <= oost;

  bool raakt(_Doos b) =>
      zuid <= b.noord && noord >= b.zuid && west <= b.oost && oost >= b.west;

  Iterable<int> vakjes() sync* {
    for (var r = (zuid / _vak).floor(); r <= (noord / _vak).floor(); r++) {
      for (var k = (west / _vak).floor(); k <= (oost / _vak).floor(); k++) {
        yield r * 100000 + k;
      }
    }
  }
}

const _vak = 0.005; // graden, ~500 m

int _vakje(double lat, double lon) =>
    (lat / _vak).floor() * 100000 + (lon / _vak).floor();

/// Plat rond [p]: op een paar kilometer op de centimeter goed.
({double x, double y}) _plat(LatLng q, LatLng p) => (
  x: (q.longitude - p.longitude) * cos(p.latitude * pi / 180) * 111320,
  y: (q.latitude - p.latitude) * 110574,
);

/// De afstand van [p] tot [lijn], de richting van de lijn op die plek, en of
/// die plek het begin of eind van de lijn is terwijl [p] er voorbij ligt.
({double afstand, double koers, bool voorbij}) _dichtsbij(
  LatLng p,
  List<LatLng> lijn,
) {
  var beste = (afstand: double.infinity, koers: 0.0, voorbij: false);
  for (var i = 0; i < lijn.length - 1; i++) {
    final a = _plat(lijn[i], p), b = _plat(lijn[i + 1], p);
    final dx = b.x - a.x, dy = b.y - a.y;
    final kwadraat = dx * dx + dy * dy;
    if (kwadraat == 0) continue;
    final ruw = (-a.x * dx - a.y * dy) / kwadraat;
    final t = ruw.clamp(0.0, 1.0);
    final x = a.x + t * dx, y = a.y + t * dy;
    final afstand = sqrt(x * x + y * y);
    if (afstand < beste.afstand) {
      beste = (
        afstand: afstand,
        koers: (atan2(dx, dy) * 180 / pi + 360) % 360,
        voorbij: (i == 0 && ruw < 0) || (i == lijn.length - 2 && ruw > 1),
      );
    }
  }
  return beste;
}

double _koers(LatLng a, LatLng b, LatLng rond) {
  final pa = _plat(a, rond), pb = _plat(b, rond);
  return (atan2(pb.x - pa.x, pb.y - pa.y) * 180 / pi + 360) % 360;
}

double _hoekVerschil(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}
