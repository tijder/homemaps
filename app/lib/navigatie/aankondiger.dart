import 'dart:math';

import '../models/profiel.dart';
import '../models/route.dart';
import 'volger.dart';

/// Beslist wat er wanneer gezegd wordt. Valhalla levert de zinnen; hier alleen
/// het moment, zodat elke zin precies één keer klinkt:
///
/// * **vooraf** ruim van tevoren ("Links afslaan naar X."), alleen als er tijd
///   genoeg is -- volgt een bocht vlak op de vorige, dan is "vlak voor" genoeg;
/// * **vlak voor** een paar seconden ervoor, met "Daarna ..." als de volgende
///   dichtbij is;
/// * **erna** ("3 kilometer doorgaan.") zodra je de bocht door bent.
class Aankondiger {
  Aankondiger(this.route, this.profiel, {required this.metAfstand});

  final RouteOptie route;
  final Profiel profiel;

  /// Zet de afstand voor een zin: Valhalla's "vooraf" en "vlak voor" zijn vaak
  /// dezelfde tekst, en twee keer precies hetzelfde horen klinkt als een fout.
  final String Function(double meters, String zin) metAfstand;
  final _gezegd = <(int, _Soort)>{};
  bool _begonnen = false;

  /// Wat er bij deze stand gezegd moet worden, in volgorde. [snelheid] in m/s.
  List<String> bij(NavStand stand, double snelheid) {
    final zinnen = <String>[];
    final m = route.manoeuvres;
    if (m.isEmpty) return zinnen;

    void zeg(int index, _Soort soort, String? zin) {
      if (_gezegd.add((index, soort)) && zin != null && zin.isNotEmpty) {
        zinnen.add(zin);
        // "Daarna, over 400 meter, ..." zat er al in: niet nog eens vooraf.
        if (soort == _Soort.vlakVoor && m[index].metVolgende) {
          _gezegd.add((index + 1, _Soort.vooraf));
        }
      }
    }

    // Het vertrek: de eerste manoeuvre beschrijft al waar je heen rijdt en wat
    // daarna komt.
    if (!_begonnen) {
      _begonnen = true;
      zeg(0, _Soort.vlakVoor, m.first.stemVlakVoor);
      _gezegd.add((0, _Soort.na));
      // Wat al voorbij is (een herberekening onderweg) niet meer.
      for (var i = 1; i < stand.volgende; i++) {
        for (final soort in _Soort.values) {
          _gezegd.add((i, soort));
        }
      }
    }

    // Net door een bocht: hoe het verder gaat.
    final vorige = stand.volgende - 1;
    if (vorige > 0 && !stand.aangekomen) {
      for (final soort in [_Soort.vooraf, _Soort.vlakVoor]) {
        _gezegd.add((vorige, soort));
      }
      zeg(vorige, _Soort.na, m[vorige].stemNa);
    }

    final volgende = m[stand.volgende];
    final afstand = stand.totVolgende;
    if (stand.aangekomen && volgende.isBestemming) {
      zeg(stand.volgende, _Soort.vooraf, null);
      zeg(stand.volgende, _Soort.vlakVoor, volgende.stemVlakVoor);
      return zinnen;
    }
    // De bestemming zelf pas bij aankomst: "Aangekomen op je bestemming" terwijl
    // je er nog 8 seconden vanaf zit, klopt niet.
    final vlakVoor = volgende.isBestemming && stand.volgende == m.length - 1
        ? -1.0
        : vlakVoorAfstand(snelheid);
    if (afstand <= vlakVoor) {
      _gezegd.add((stand.volgende, _Soort.vooraf));
      zeg(stand.volgende, _Soort.vlakVoor, volgende.stemVlakVoor);
    } else {
      final vooraf = voorafAfstand(snelheid);
      // Alleen in het venster: kom je er pas binnen op 60% van de afstand (een
      // kort stuk na de vorige bocht), dan is het te laat voor "vooraf".
      if (afstand <= vooraf && afstand >= vooraf * 0.6) {
        final zin = volgende.stemVooraf;
        zeg(
          stand.volgende,
          _Soort.vooraf,
          zin == null ? null : metAfstand(afstand, zin),
        );
      }
    }
    return zinnen;
  }

  /// Ruim van tevoren: ongeveer 35 seconden, binnen grenzen per vervoermiddel.
  double voorafAfstand(double snelheid) {
    final (laag, hoog) = switch (profiel) {
      Profiel.auto => (300.0, 1500.0),
      Profiel.fiets => (120.0, 300.0),
      Profiel.lopen => (50.0, 120.0),
    };
    return (snelheid * 35).clamp(laag, hoog);
  }

  /// Vlak voor: ongeveer 8 seconden, met een minimum voor wie stilstaat.
  double vlakVoorAfstand(double snelheid) {
    final minimum = switch (profiel) {
      Profiel.auto => 60.0,
      Profiel.fiets => 30.0,
      Profiel.lopen => 15.0,
    };
    return max(minimum, snelheid * 8 + 15);
  }
}

enum _Soort { vooraf, vlakVoor, na }
