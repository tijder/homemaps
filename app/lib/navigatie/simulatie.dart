import 'dart:async';
import 'dart:math';

import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/route.dart';
import '../providers/locatie.dart';
import '../utils/afstand.dart';

/// Een nagemaakte GPS die de route afrijdt, om navigatie te testen zonder te
/// rijden. Op het web aan te zetten met `?simulatie=52.186,5.7035` (het
/// startpunt), eventueel met `&snelheid=14` (m/s) en `&mis=3` (bij manoeuvre 3
/// rechtdoor rijden, zodat er herberekend moet worden).
class SimulatieBron implements LocatieBron {
  SimulatieBron(this._plek, {this.snelheid = 14, this.misBij});

  LatLng _plek;
  final double snelheid;
  final int? misBij;

  List<LatLng>? _pad;
  List<double> _tot = const [];
  double _afgelegd = 0;
  double _koers = 0;
  double? _misBijMeter;
  bool _gemist = false;

  /// Stil (begin of aangekomen), langs de route, of rechtdoor na een gemiste
  /// afslag.
  var _modus = _Modus.stil;

  /// Vanaf nu deze route afrijden (de navigatie roept dit bij elke nieuwe of
  /// herberekende route aan).
  void rijd(RouteOptie route) {
    _pad = route.punten;
    _tot = [0];
    for (var i = 1; i < route.punten.length; i++) {
      _tot.add(_tot.last + meters(route.punten[i - 1], route.punten[i]));
    }
    _afgelegd = 0;
    _modus = _Modus.route;
    final index = misBij;
    _misBijMeter = !_gemist && index != null && index < route.manoeuvres.length
        ? _tot[route.manoeuvres[index].vormIndex]
        : null;
  }

  @override
  Future<Toestemming> controleer() async => Toestemming.ja;

  @override
  Future<Toestemming> vraag() async => Toestemming.ja;

  @override
  Stream<LocatieFix> volg({
    required bool nauwkeurig,
    ({String titel, String tekst})? melding,
  }) {
    late final StreamController<LocatieFix> uit;
    Timer? tik;
    uit = StreamController<LocatieFix>(
      onListen: () {
        uit.add(_fix(0));
        tik = Timer.periodic(
          const Duration(seconds: 1),
          (_) => uit.add(_fix(snelheid)),
        );
      },
      onCancel: () => tik?.cancel(),
    );
    return uit.stream;
  }

  LocatieFix _fix(double stap) {
    switch (_modus) {
      case _Modus.stil:
        break;
      case _Modus.route:
        _langsRoute(stap);
      case _Modus.rechtdoor:
        final r = _koers * pi / 180;
        _plek = LatLng(
          _plek.latitude + stap * cos(r) / 110574,
          _plek.longitude +
              stap * sin(r) / (111320 * cos(_plek.latitude * pi / 180)),
        );
    }
    final rijdt = _modus != _Modus.stil;
    return LocatieFix(
      punt: _plek,
      tijd: DateTime.now(),
      nauwkeurigheid: 5,
      koers: rijdt ? _koers : null,
      snelheid: rijdt ? snelheid : 0,
    );
  }

  void _langsRoute(double stap) {
    final pad = _pad!;
    _afgelegd += stap;
    final mis = _misBijMeter;
    if (mis != null && _afgelegd >= mis) {
      // De afslag missen: rechtdoor, van de route af, tot er een nieuwe is.
      _gemist = true;
      _modus = _Modus.rechtdoor;
      return;
    }
    if (_afgelegd >= _tot.last) {
      _plek = pad.last;
      _modus = _Modus.stil;
      return;
    }
    var i = 0;
    while (_tot[i + 1] < _afgelegd) {
      i++;
    }
    final t = (_afgelegd - _tot[i]) / max(_tot[i + 1] - _tot[i], 0.001);
    final a = pad[i], b = pad[i + 1];
    _plek = LatLng(
      a.latitude + t * (b.latitude - a.latitude),
      a.longitude + t * (b.longitude - a.longitude),
    );
    if (meters(a, b) > 0.5) _koers = _richting(a, b);
  }

  static double _richting(LatLng a, LatLng b) {
    final f1 = a.latitude * pi / 180, f2 = b.latitude * pi / 180;
    final dl = (b.longitude - a.longitude) * pi / 180;
    return (atan2(
                  sin(dl) * cos(f2),
                  cos(f1) * sin(f2) - sin(f1) * cos(f2) * cos(dl),
                ) *
                180 /
                pi +
            360) %
        360;
  }

  /// Uit de URL van de web-app, of null als daar geen simulatie in staat.
  static SimulatieBron? uitUrl(Uri url) {
    final start = url.queryParameters['simulatie']?.split(',');
    if (start == null || start.length != 2) return null;
    final lat = double.tryParse(start[0]), lon = double.tryParse(start[1]);
    if (lat == null || lon == null) return null;
    return SimulatieBron(
      LatLng(lat, lon),
      snelheid: double.tryParse(url.queryParameters['snelheid'] ?? '') ?? 14,
      misBij: int.tryParse(url.queryParameters['mis'] ?? ''),
    );
  }
}

enum _Modus { stil, route, rechtdoor }
