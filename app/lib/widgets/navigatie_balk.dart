import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../navigatie/navigatie_provider.dart';
import '../utils/opmaak.dart';
import 'manoeuvre_pictogram.dart';

/// Bovenaan tijdens navigatie: de volgende manoeuvre, groot, en de manoeuvre
/// daarna klein als die er vlak achteraan komt.
class NavigatieKop extends StatelessWidget {
  const NavigatieKop(this.nav, {super.key});

  final NavigatieToestand nav;

  /// Komt de manoeuvre daarna binnen zoveel meter, dan staat hij er al bij.
  static const _daarnaBinnen = 300.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final kleuren = Theme.of(context).colorScheme;
    final tekst = Theme.of(context).textTheme;
    final stand = nav.stand;
    final manoeuvres = nav.route.manoeuvres;

    final (IconData pictogram, String titel, String? onder) = nav.aangekomen
        ? (Icons.flag, l.aangekomen, nav.doelen.lastOrNull?.weergave(l))
        : nav.herberekent
        ? (Icons.sync, l.herberekenenBezig, null)
        : stand == null
        ? (Icons.navigation, l.locatieZoeken, null)
        : (
            manoeuvrePictogram(manoeuvres[stand.volgende].type),
            afstand(_rond(stand.totVolgende)),
            manoeuvres[stand.volgende].instructie,
          );

    final daarna = stand != null && !nav.aangekomen && !nav.herberekent
        ? stand.volgende + 1
        : null;
    final toonDaarna =
        daarna != null &&
        daarna < manoeuvres.length &&
        manoeuvres[stand!.volgende].meters < _daarnaBinnen;

    return Material(
      color: kleuren.primaryContainer,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
            child: Row(
              children: [
                Icon(pictogram, size: 56, color: kleuren.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        titel,
                        style: tekst.headlineMedium?.copyWith(
                          color: kleuren.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (onder != null)
                        Text(
                          onder,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tekst.titleMedium?.copyWith(
                            color: kleuren.onPrimaryContainer,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (toonDaarna)
            Container(
              color: kleuren.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Text(
                    l.daarna,
                    style: tekst.titleSmall?.copyWith(color: kleuren.onPrimary),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    manoeuvrePictogram(manoeuvres[daarna].type),
                    color: kleuren.onPrimary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Een afstand die niet bij elke meter verspringt: onder de 100 m op 10 m,
  /// daarboven op 50 m.
  static double _rond(double meters) => meters < 100
      ? (meters / 10).round() * 10
      : meters < 1000
      ? (meters / 50).round() * 50
      : meters;
}

/// Onderaan tijdens navigatie: aankomsttijd, wat er nog rest, stem en stop.
class NavigatieVoet extends StatelessWidget {
  const NavigatieVoet(
    this.nav, {
    super.key,
    required this.onStop,
    required this.onDempen,
  });

  final NavigatieToestand nav;
  final VoidCallback onStop;
  final ValueChanged<bool> onDempen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tekst = Theme.of(context).textTheme;
    final stand = nav.stand;
    final seconden = stand?.restSeconden ?? nav.route.seconden;
    final meters = stand?.restMeters ?? nav.route.meters;
    final aankomst = DateTime.now().add(Duration(seconds: seconden.round()));
    final taal = Localizations.localeOf(context).languageCode;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: nav.aangekomen
                  ? Text(l.aangekomen, style: tekst.titleLarge)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l.aankomst(DateFormat.Hm(taal).format(aankomst)),
                          style: tekst.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${duur(seconden)} · ${afstand(meters)}',
                          style: tekst.bodyMedium,
                        ),
                      ],
                    ),
            ),
            if (!nav.aangekomen)
              IconButton(
                tooltip: nav.gedempt ? l.stemAan : l.stemUit,
                icon: Icon(nav.gedempt ? Icons.volume_off : Icons.volume_up),
                onPressed: () => onDempen(!nav.gedempt),
              ),
            const SizedBox(width: 4),
            FilledButton.icon(
              style: nav.aangekomen
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
              onPressed: onStop,
              icon: Icon(nav.aangekomen ? Icons.check : Icons.close),
              label: Text(nav.aangekomen ? l.klaar : l.stopNavigatie),
            ),
          ],
        ),
      ),
    );
  }
}
