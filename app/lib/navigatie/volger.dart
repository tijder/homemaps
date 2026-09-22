import 'dart:math';

import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/route.dart';
import '../providers/locatie.dart';
import '../utils/afstand.dart';

/// Waar je bent ten opzichte van de route, na één fix.
class NavStand {
  const NavStand({
    required this.opRoute,
    required this.langs,
    required this.afwijking,
    required this.routeKoers,
    required this.volgende,
    required this.totVolgende,
    required this.restMeters,
    required this.restSeconden,
    required this.vanRoute,
    required this.aangekomen,
  });

  /// Het punt op de route dat het dichtst bij de fix ligt.
  final LatLng opRoute;

  /// Meters vanaf het begin van de route tot [opRoute].
  final double langs;

  /// Meters tussen de fix en de route.
  final double afwijking;

  /// De richting van de route hier, in graden.
  final double routeKoers;

  /// Index in [RouteOptie.manoeuvres] van de eerstvolgende manoeuvre.
  final int volgende;
  final double totVolgende;
  final double restMeters;
  final double restSeconden;

  /// Meerdere fixes op rij te ver van de route (of de verkeerde kant op).
  final bool vanRoute;
  final bool aangekomen;
}

/// Legt fixes op één route. Houdt bij waar je was, zodat een weg die vlak naast
/// zichzelf terugkomt (een klaverblad, een haarspeld) niet laat verspringen.
class RouteVolger {
  RouteVolger(this.route) : _tot = _cumulatief(route.punten);

  final RouteOptie route;

  /// Meters vanaf het begin tot elk punt van de vorm.
  final List<double> _tot;

  int? _segment;
  int _teVer = 0;

  /// Zo ver mag een fix van de route liggen (plus twee keer zijn onzekerheid).
  static const maxAfwijking = 35.0;

  /// Zoveel fixes op rij te ver weg voordat het "van de route" is.
  static const fixesTotVanRoute = 3;

  /// Binnen zoveel meter van het eind ben je er.
  static const aankomstStraal = 25.0;

  double get lengte => _tot.isEmpty ? 0 : _tot.last;

  double totManoeuvre(int index) =>
      _tot[route.manoeuvres[index].vormIndex.clamp(0, _tot.length - 1)];

  static List<double> _cumulatief(List<LatLng> punten) {
    final tot = <double>[0];
    for (var i = 1; i < punten.length; i++) {
      tot.add(tot.last + meters(punten[i - 1], punten[i]));
    }
    return tot;
  }

  NavStand werkBij(LocatieFix fix) {
    final punten = route.punten;
    // Eerst alleen vlak om de vorige plek: iets terug (ruis) en een eind vooruit.
    // Pas als daar niets in de buurt ligt, de hele route.
    final vorige = _segment;
    var beste = vorige == null
        ? _zoek(fix.punt, 0, punten.length - 2)
        : _zoek(
            fix.punt,
            max(0, vorige - 3),
            _segmentNa(_tot[vorige] + 400 + (fix.snelheid ?? 0) * 10),
          );
    if (vorige != null && beste.afstand > maxAfwijking) {
      final overal = _zoek(fix.punt, 0, punten.length - 2);
      // Alleen verspringen als het elders duidelijk beter past; anders ben je
      // gewoon van de route.
      if (overal.afstand < beste.afstand / 2) beste = overal;
    }
    final segment = beste.segment;

    final grens = maxAfwijking + 2 * min(fix.nauwkeurigheid, 50);
    final koers = _koers(punten[segment], punten[segment + 1]);
    final tegen =
        fix.koers != null &&
        (fix.snelheid ?? 0) > 5 &&
        _hoekVerschil(fix.koers!, koers) > 100;
    if (beste.afstand > grens || tegen) {
      _teVer++;
    } else {
      _teVer = 0;
      _segment = segment;
    }
    _segment ??= segment;

    final langs =
        _tot[segment] + beste.fractie * (_tot[segment + 1] - _tot[segment]);
    final manoeuvres = route.manoeuvres;
    var volgende = manoeuvres.length - 1;
    for (var i = 0; i < manoeuvres.length; i++) {
      // Een paar meter speling: wie net door de bocht is, heeft hem gehad.
      if (totManoeuvre(i) > langs + 5) {
        volgende = i;
        break;
      }
    }
    final rest = max(0.0, lengte - langs);
    return NavStand(
      opRoute: beste.punt,
      langs: langs,
      afwijking: beste.afstand,
      routeKoers: koers,
      volgende: volgende,
      totVolgende: max(0.0, totManoeuvre(volgende) - langs),
      restMeters: rest,
      restSeconden: _restTijd(langs),
      vanRoute: _teVer >= fixesTotVanRoute,
      aangekomen: rest < aankomstStraal && beste.afstand < 50,
    );
  }

  /// De tijd van elke manoeuvre geldt voor zijn eigen stuk; van het stuk waar je
  /// nu op zit telt alleen wat er nog over is.
  double _restTijd(double langs) {
    var rest = 0.0;
    for (final m in route.manoeuvres) {
      final begin = _tot[m.vormIndex.clamp(0, _tot.length - 1)];
      final eind = _tot[m.eindVormIndex.clamp(0, _tot.length - 1)];
      if (eind <= langs) continue;
      if (begin >= langs || eind <= begin) {
        rest += m.seconden;
      } else {
        rest += m.seconden * (eind - langs) / (eind - begin);
      }
    }
    return rest;
  }

  int _segmentNa(double afstand) {
    var i = _segment ?? 0;
    while (i < _tot.length - 2 && _tot[i] < afstand) {
      i++;
    }
    return i;
  }

  ({int segment, double fractie, double afstand, LatLng punt}) _zoek(
    LatLng p,
    int van,
    int tot,
  ) {
    final punten = route.punten;
    var beste = (segment: van, fractie: 0.0, afstand: double.infinity, punt: p);
    // Een platte projectie rond de fix: op een paar kilometer is dat op de
    // centimeter goed, en veel sneller dan bolmeetkunde per segment.
    final kosLat = cos(p.latitude * pi / 180);
    ({double x, double y}) plat(LatLng q) => (
      x: (q.longitude - p.longitude) * kosLat * 111320,
      y: (q.latitude - p.latitude) * 110574,
    );
    for (var i = van; i <= tot && i < punten.length - 1; i++) {
      final a = plat(punten[i]), b = plat(punten[i + 1]);
      final dx = b.x - a.x, dy = b.y - a.y;
      final kwadraat = dx * dx + dy * dy;
      final t = kwadraat == 0
          ? 0.0
          : ((-a.x * dx - a.y * dy) / kwadraat).clamp(0.0, 1.0);
      final x = a.x + t * dx, y = a.y + t * dy;
      final afstand = sqrt(x * x + y * y);
      if (afstand < beste.afstand) {
        final a0 = punten[i], b0 = punten[i + 1];
        beste = (
          segment: i,
          fractie: t,
          afstand: afstand,
          punt: LatLng(
            a0.latitude + t * (b0.latitude - a0.latitude),
            a0.longitude + t * (b0.longitude - a0.longitude),
          ),
        );
      }
    }
    return beste;
  }
}

double _koers(LatLng a, LatLng b) {
  final f1 = a.latitude * pi / 180, f2 = b.latitude * pi / 180;
  final dl = (b.longitude - a.longitude) * pi / 180;
  final y = sin(dl) * cos(f2);
  final x = cos(f1) * sin(f2) - sin(f1) * cos(f2) * cos(dl);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}

double _hoekVerschil(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}
