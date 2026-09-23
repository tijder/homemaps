import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/route.dart';
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

    final volgende = stand != null && !nav.aangekomen && !nav.herberekent
        ? manoeuvres[stand.volgende]
        : null;
    final (Widget pictogram, String titel, String? onder) = nav.aangekomen
        ? (
            _icoon(Icons.flag, kleuren),
            l.aangekomen,
            nav.doelen.lastOrNull?.weergave(l),
          )
        : nav.herberekent
        ? (_icoon(Icons.sync, kleuren), l.herberekenenBezig, null)
        : stand == null
        ? (_icoon(Icons.navigation, kleuren), l.locatieZoeken, null)
        : (
            ManoeuvreIcoon(
              manoeuvres[stand.volgende],
              size: 56,
              color: kleuren.onPrimaryContainer,
            ),
            afstand(_rond(stand.totVolgende)),
            manoeuvres[stand.volgende].instructie,
          );
    // Bij een op- of afrit, splitsing of invoegstrook, zoals bij Google en
    // Apple Maps: kort wat je doet, met het bord eronder, in plaats van de
    // hele zin.
    final bord = volgende?.wegwijzer;
    final actie = bord == null ? null : korteActie(volgende!, l);
    final rijstroken = volgende == null ? null : nav.rijstroken;
    final matrix = nav.aangekomen ? null : nav.matrix;

    // Na "rotonde op" komt "rotonde af", met dezelfde uitrit: die staat al in
    // het grote pictogram. Dan pas wat erna komt.
    var daarna = stand != null && !nav.aangekomen && !nav.herberekent
        ? stand.volgende + 1
        : null;
    var tussen = volgende?.meters ?? 0;
    if (daarna != null &&
        daarna < manoeuvres.length &&
        volgende?.type == 26 &&
        manoeuvres[daarna].type == 27) {
      tussen += manoeuvres[daarna].meters;
      daarna++;
    }
    final toonDaarna =
        daarna != null && daarna < manoeuvres.length && tussen < _daarnaBinnen;

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
                pictogram,
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
                      if (bord != null) ...[
                        if (actie != null)
                          Text(
                            actie,
                            style: tekst.titleMedium?.copyWith(
                              color: kleuren.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 6),
                        WegBord(bord),
                      ] else if (onder != null)
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
          // De matrixborden gaan voor: daar staat wat nu geldt.
          if (matrix != null)
            MatrixBalk(matrix.stroken)
          else if (rijstroken != null)
            RijstrookBalk(
              rijstroken.stroken,
              // Een kruising vóór de manoeuvre: zijn eigen afstand erbij, anders
              // lijkt het de afslag hierboven.
              over: rijstroken.bijManoeuvre ? null : rijstroken.over,
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
                  ManoeuvreIcoon(manoeuvres[daarna], color: kleuren.onPrimary),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Widget _icoon(IconData pictogram, ColorScheme kleuren) =>
      Icon(pictogram, size: 56, color: kleuren.onPrimaryContainer);

  /// Een afstand die niet bij elke meter verspringt: onder de 100 m op 10 m,
  /// daarboven op 50 m.
  static double _rond(double meters) => meters < 100
      ? (meters / 10).round() * 10
      : meters < 1000
      ? (meters / 50).round() * 50
      : meters;
}

/// Kort wat je doet bij een op- of afrit, splitsing of invoegstrook ("Links
/// aanhouden"), of null bij een andere manoeuvre.
String? korteActie(Manoeuvre manoeuvre, AppLocalizations l) {
  final soort = switch (manoeuvre.type) {
    17 || 18 || 19 => 'oprit',
    20 || 21 => 'afrit',
    22 => 'rechtdoor',
    23 => 'rechts',
    24 => 'links',
    25 || 37 || 38 => 'invoegen',
    _ => null,
  };
  return soort == null ? null : l.korteActie(soort);
}

/// Een bord zoals langs de snelweg: het afritnummer, de wegnummers (A-wegen
/// rood, N-wegen geel, zoals in Nederland) en de richtingen.
class WegBord extends StatelessWidget {
  const WegBord(this.bord, {super.key});

  final Bord bord;

  static const _blauw = Color(0xFF0A4C9A);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tekst = Theme.of(context).textTheme;
    final richtingen = bord.richtingen.isNotEmpty
        ? bord.richtingen.take(3).join(' · ')
        : bord.naam;
    Widget schildje(String inhoud, Color achter, Color voor) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: achter,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        inhoud,
        style: tekst.labelLarge?.copyWith(
          color: voor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _blauw,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (bord.afrit case final afrit?)
            schildje(l.afrit(afrit), Colors.white, _blauw),
          for (final weg in bord.wegen.take(2))
            if (weg.startsWith('A') || weg.startsWith('E'))
              schildje(
                weg,
                weg.startsWith('E')
                    ? const Color(0xFF00843D)
                    : const Color(0xFFD2232A),
                Colors.white,
              )
            else if (weg.startsWith('N'))
              schildje(weg, const Color(0xFFFFD200), Colors.black)
            else
              schildje(weg, _blauw, Colors.white),
          if (richtingen != null)
            Text(
              richtingen,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tekst.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

/// De rijstroken bij een kruising: goede vol, de rest gedimd. Met [over] staat
/// links hoe ver die kruising nog is.
class RijstrookBalk extends StatelessWidget {
  const RijstrookBalk(this.stroken, {this.over, super.key});

  final List<Rijstrook> stroken;

  /// Hoe ver de kruising nog is, als dat niet die van de manoeuvre is.
  final double? over;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final kleuren = Theme.of(context).colorScheme;
    final goed = l.rijstrokenGoed(
      stroken.where((s) => s.goed).length,
      stroken.length,
    );
    final over = this.over;
    final afstandTekst = over == null
        ? null
        : afstand(NavigatieKop._rond(over));
    return Semantics(
      label: afstandTekst == null ? goed : l.rijstrokenOver(afstandTekst, goed),
      excludeSemantics: true,
      child: Container(
        color: kleuren.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            if (afstandTekst != null)
              Text(
                afstandTekst,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: kleuren.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final (i, strook) in stroken.indexed) ...[
                    if (i > 0)
                      Container(
                        width: 1,
                        height: 28,
                        color: kleuren.onPrimary.withValues(alpha: 0.3),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: _strook(strook, kleuren),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _strook(Rijstrook strook, ColorScheme kleuren) {
    // Een goede strook met meer richtingen: alleen die je neemt, anders past
    // het niet en zegt het minder.
    final richtingen = strook.goed && strook.gebruik != null
        ? [strook.gebruik!]
        : strook.richtingen.isEmpty
        ? const ['straight']
        : strook.richtingen;
    final kleur = strook.goed
        ? kleuren.onPrimary
        : kleuren.onPrimary.withValues(alpha: 0.35);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final richting in richtingen.take(2))
          Icon(
            rijstrookPictogram(richting),
            size: richtingen.length > 1 ? 22 : 30,
            color: kleur,
          ),
      ],
    );
  }
}

/// Het eerstvolgende portaal met matrixborden, per strook van links naar
/// rechts, zoals het boven de weg hangt.
class MatrixBalk extends StatelessWidget {
  const MatrixBalk(this.stroken, {super.key});

  /// Codes zoals in [Portaal]: "70", "70r", "x", "<", ">", "open", "einde", "".
  final List<String> stroken;

  static const _rood = Color(0xFFD32F2F);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Semantics(
      label: l.matrixborden,
      child: Container(
        color: const Color(0xFF263238),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final strook in stroken)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _beeld(strook),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _beeld(String strook) {
    Icon icoon(IconData pictogram, Color kleur) =>
        Icon(pictogram, color: kleur, size: 28);
    const wit = Colors.white;
    return switch (strook) {
      'x' => icoon(Icons.close, _rood),
      '<' => icoon(Icons.south_west, wit),
      '>' => icoon(Icons.south_east, wit),
      'open' => icoon(Icons.arrow_downward, const Color(0xFF43A047)),
      'einde' => icoon(Icons.block, Colors.white70),
      '' => const SizedBox.shrink(),
      _ => _snelheid(strook),
    };
  }

  static Widget _snelheid(String strook) {
    final verplicht = strook.endsWith('r');
    final getal = verplicht ? strook.substring(0, strook.length - 1) : strook;
    final tekst = Text(
      getal,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    if (!verplicht) return tekst;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _rood, width: 3),
      ),
      child: tekst,
    );
  }
}

/// Onderaan tijdens navigatie: aankomsttijd, wat er nog rest, stem en stop.
class NavigatieVoet extends StatelessWidget {
  const NavigatieVoet(
    this.nav, {
    super.key,
    required this.onStop,
    required this.onDempen,
    this.onZoekLangs,
  });

  final NavigatieToestand nav;
  final VoidCallback onStop;
  final ValueChanged<bool> onDempen;

  /// "Langs de route" (tanken, laden, ...): een stop toevoegen.
  final VoidCallback? onZoekLangs;

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
            if (!nav.aangekomen && onZoekLangs != null)
              IconButton(
                tooltip: l.langsDeRoute,
                icon: const Icon(Icons.local_gas_station_outlined),
                onPressed: onZoekLangs,
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

/// Een snellere route onderweg: nemen of negeren. Een balkje loopt leeg tot het
/// voorstel vanzelf vervalt (dan blijft de huidige route).
class VoorstelKaart extends StatelessWidget {
  const VoorstelKaart(
    this.voorstel, {
    super.key,
    required this.onNemen,
    required this.onNegeren,
  });

  final Voorstel voorstel;
  final VoidCallback onNemen;
  final VoidCallback onNegeren;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tekst = Theme.of(context).textTheme;
    final kleuren = Theme.of(context).colorScheme;
    final over = voorstel.verloopt.difference(DateTime.now());
    final minuten = (voorstel.secondenSneller / 60).round();
    final via = voorstel.via;
    return Material(
      elevation: 8,
      color: kleuren.tertiaryContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Van vol naar leeg in de tijd die het voorstel nog heeft.
          TweenAnimationBuilder<double>(
            tween: Tween(
              begin:
                  over.inMilliseconds /
                  NavigatieNotifier.voorstelDuur.inMilliseconds,
              end: 0,
            ),
            duration: over.isNegative ? Duration.zero : over,
            builder: (context, waarde, _) => LinearProgressIndicator(
              value: waarde.clamp(0, 1),
              minHeight: 3,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: Row(
              children: [
                Icon(Icons.alt_route, color: kleuren.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.voorstelSneller(minuten),
                        style: tekst.titleMedium?.copyWith(
                          color: kleuren.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (via != null)
                        Text(
                          l.voorstelVia(via),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tekst.bodyMedium?.copyWith(
                            color: kleuren.onTertiaryContainer,
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton(onPressed: onNegeren, child: Text(l.negeren)),
                const SizedBox(width: 4),
                FilledButton(onPressed: onNemen, child: Text(l.nemen)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Linksonder tijdens autonavigatie: het verkeersbord met de maximumsnelheid
/// (als die bekend is) en je eigen snelheid, rood als je er ruim overheen zit.
/// Een tijdelijke limiet (bij werk) krijgt een werk-pictogram; een limiet van
/// de matrixborden staat wit op zwart, zoals boven de weg.
class SnelheidBord extends StatelessWidget {
  const SnelheidBord({
    super.key,
    required this.limiet,
    required this.snelheid,
    this.bron = LimietBron.osm,
  });

  final int? limiet;
  final LimietBron bron;

  /// In m/s, of null als onbekend.
  final double? snelheid;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final kleuren = Theme.of(context).colorScheme;
    final kmu = snelheid == null ? null : (snelheid! * 3.6).round();
    final teHard = limiet != null && kmu != null && kmu > limiet! + 5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (limiet != null)
          Semantics(
            label: switch (bron) {
              LimietBron.werk => l.maximumsnelheidTijdelijk(limiet!),
              LimietBron.msi => l.maximumsnelheidMatrix(limiet!),
              _ => l.maximumsnelheid(limiet!),
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bron == LimietBron.msi ? Colors.black : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFD32F2F),
                      width: 6,
                    ),
                    boxShadow: const [
                      BoxShadow(blurRadius: 4, color: Colors.black26),
                    ],
                  ),
                  child: Text(
                    '$limiet',
                    style: TextStyle(
                      color: bron == LimietBron.msi
                          ? Colors.white
                          : Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (bron == LimietBron.werk)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9A825),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.construction,
                        size: 14,
                        color: Colors.black,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (kmu != null) ...[
          const SizedBox(height: 6),
          Material(
            elevation: 4,
            color: teHard ? kleuren.error : kleuren.surface,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Column(
                children: [
                  Text(
                    '$kmu',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: teHard ? kleuren.onError : kleuren.onSurface,
                    ),
                  ),
                  Text(
                    l.kmu,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: teHard ? kleuren.onError : kleuren.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
