import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/route.dart';
import '../utils/opmaak.dart';
import 'manoeuvre_pictogram.dart';
import 'navigatie_balk.dart';

/// De routebeschrijving: per stap het pictogram, wat je doet (kort met het
/// bord bij op- en afritten, anders de zin) en een afstand.
///
/// Met [totVolgende] (onderweg) staat bij elke stap hoe ver die nog is, vanaf
/// [vanaf]; zonder (bij het plannen) hoe lang het stuk erna is.
class StappenLijst extends StatelessWidget {
  const StappenLijst(this.route, {this.vanaf = 0, this.totVolgende, super.key});

  final RouteOptie route;
  final int vanaf;
  final double? totVolgende;

  /// De stappen die een eigen regel krijgen, met hun afstand.
  @visibleForTesting
  static List<({Manoeuvre manoeuvre, double meters})> stappen(
    RouteOptie route, {
    int vanaf = 0,
    double? totVolgende,
  }) {
    final m = route.manoeuvres;
    final uit = <({Manoeuvre manoeuvre, double meters})>[];
    var over = totVolgende ?? 0;
    for (var i = vanaf; i < m.length; i++) {
      final samen = uit.isNotEmpty && _zonderEigenRegel(m[i], m[i - 1]);
      if (totVolgende != null) {
        if (!samen) uit.add((manoeuvre: m[i], meters: over));
        over += m[i].meters;
      } else if (samen) {
        // Het stuk erna hoort bij de regel ervoor.
        final vorige = uit.removeLast();
        uit.add((
          manoeuvre: vorige.manoeuvre,
          meters: vorige.meters + m[i].meters,
        ));
      } else {
        uit.add((manoeuvre: m[i], meters: m[i].meters));
      }
    }
    return uit;
  }

  /// Doorgaan (7, 8) zonder bord, rotonde af (27) na rotonde op (26), en een
  /// tweede afrit met hetzelfde nummer (Valhalla splitst de afritstrook soms
  /// in tweeën): die zeggen niets wat de regel ervoor niet al zegt.
  static bool _zonderEigenRegel(Manoeuvre m, Manoeuvre vorige) =>
      ((m.type == 7 || m.type == 8) && m.bord == null) ||
      (m.type == 27 && vorige.type == 26) ||
      (_isAfrit(m) &&
          _isAfrit(vorige) &&
          m.bord?.afrit != null &&
          m.bord?.afrit == vorige.bord?.afrit);

  static bool _isAfrit(Manoeuvre m) => m.type == 20 || m.type == 21;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tekst = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final stap in stappen(
          route,
          vanaf: vanaf,
          totVolgende: totVolgende,
        ))
          _regel(stap.manoeuvre, stap.meters, l, tekst),
      ],
    );
  }

  Widget _regel(
    Manoeuvre manoeuvre,
    double meters,
    AppLocalizations l,
    TextTheme tekst,
  ) {
    final bord = manoeuvre.wegwijzer;
    final actie = bord == null ? null : korteActie(manoeuvre, l);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 32, child: ManoeuvreIcoon(manoeuvre)),
          const SizedBox(width: 12),
          Expanded(
            child: bord == null
                ? Text(manoeuvre.instructie)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (actie != null)
                        Text(
                          actie,
                          style: tekst.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 4),
                      WegBord(bord),
                    ],
                  ),
          ),
          if (meters > 0 || totVolgende != null) ...[
            const SizedBox(width: 12),
            Text(
              afstand(
                totVolgende == null ? meters : rondAfstand(meters),
                l.localeName,
              ),
              style: tekst.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}
