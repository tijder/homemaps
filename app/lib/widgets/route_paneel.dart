import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../l10n/app_localizations.dart';
import 'langs_route.dart';
import 'locatie_reden.dart';
import 'manoeuvre_pictogram.dart';
import '../models/plaats.dart';
import '../models/profiel.dart';
import '../models/route.dart';
import '../providers/instellingen.dart';
import '../providers/locatie.dart';
import '../providers/planner.dart';
import '../services/valhalla_service.dart';
import '../utils/geplande_afsluitingen.dart';
import '../utils/opmaak.dart';
import 'hoogteprofiel.dart';
import 'zoekveld.dart';

/// Het paneel naast (breed scherm) of onder (smal scherm) de kaart: de punten,
/// de vervoerswijze, de opties en de uitkomst.
///
/// Smal ([compact]) en met een complete route staat de uitkomst voorop: één
/// regel "van → naar" (tik om te wijzigen), dan de routes en Start. De velden
/// komen pas terug als je gaat wijzigen, en klappen weer in zodra de route rond
/// is.
class RoutePaneel extends ConsumerStatefulWidget {
  const RoutePaneel({
    super.key,
    required this.nabij,
    this.mijnLocatie,
    this.onNavigeer,
    this.onLocatieAan,
    this.scroll,
    this.compact = false,
  });

  final LatLng? Function() nabij;

  /// Zie [Zoekveld.mijnLocatie].
  final Future<Plaats?> Function()? mijnLocatie;

  /// "Start": navigeer de gekozen route.
  final ValueChanged<RouteOptie>? onNavigeer;

  /// Zet je locatie aan (met de toestemmingsvraag): navigeren kan pas daarna.
  final VoidCallback? onLocatieAan;
  final ScrollController? scroll;

  /// In het bottomsheet van een smal scherm.
  final bool compact;

  @override
  ConsumerState<RoutePaneel> createState() => _RoutePaneelState();
}

class _RoutePaneelState extends ConsumerState<RoutePaneel> {
  /// Smal: de velden staan open. Vanzelf zolang de route niet rond is.
  late bool _bewerken = !ref.read(plannerProvider).compleet;

  void _zetBewerken(bool aan) {
    setState(() => _bewerken = aan);
    // Terug naar boven: anders staat de samenvatting of het eerste veld
    // buiten beeld.
    final scroll = widget.scroll;
    if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    // Rond geworden (het laatste punt gekozen): inklappen. Weer onvolledig
    // (een punt gewist): open.
    ref.listen(plannerProvider.select((p) => p.compleet), (oud, nieuw) {
      if (nieuw != oud) _zetBewerken(!nieuw);
    });
    final planner = ref.watch(plannerProvider);
    final samengevat = widget.compact && planner.compleet && !_bewerken;

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: samengevat
          ? [
              _samenvatting(planner),
              const SizedBox(height: 4),
              _uitkomst(planner),
              const Divider(height: 24),
              _profiel(),
              _vertrek(planner),
              _opties(),
              _details(planner),
            ]
          : [
              _kop(planner),
              const SizedBox(height: 4),
              _profiel(),
              _vertrek(planner),
              const SizedBox(height: 4),
              _velden(planner),
              _viaRij(),
              _opties(),
              const Divider(),
              _uitkomst(planner),
              _details(planner),
            ],
    );
  }

  Widget _kop(PlannerState planner) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        IconButton(
          tooltip: l.terugNaarZoeken,
          onPressed: ref.read(plannerProvider.notifier).naarZoeken,
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(l.route, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (widget.compact && planner.compleet)
          TextButton(
            onPressed: () => _zetBewerken(false),
            child: Text(l.klaar),
          ),
      ],
    );
  }

  /// Eén regel: van → naar (en hoeveel tussenpunten), tik om te wijzigen.
  Widget _samenvatting(PlannerState planner) {
    final l = AppLocalizations.of(context);
    final tekst = Theme.of(context).textTheme;
    final punten = [for (final p in planner.punten) p.plaats!];
    final vias = punten.length - 2;
    return Row(
      children: [
        IconButton(
          tooltip: l.terugNaarZoeken,
          onPressed: ref.read(plannerProvider.notifier).naarZoeken,
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _zetBewerken(true),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${punten.first.weergave(l)} → '
                          '${punten.last.weergave(l)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tekst.titleMedium,
                        ),
                        if (vias > 0)
                          Text(
                            l.aantalTussenpunten(vias),
                            style: tekst.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: l.routeWijzigen,
                    child: const Icon(Icons.edit_outlined, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _profiel() {
    final l = AppLocalizations.of(context);
    final instellingen = ref.watch(instellingenProvider);
    final zet = ref.read(instellingenProvider.notifier).wijzig;
    return SegmentedButton<Profiel>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: Profiel.auto,
          icon: const Icon(Icons.directions_car),
          label: Text(l.profielAuto),
        ),
        ButtonSegment(
          value: Profiel.fiets,
          icon: const Icon(Icons.directions_bike),
          label: Text(l.profielFiets),
        ),
        ButtonSegment(
          value: Profiel.lopen,
          icon: const Icon(Icons.directions_walk),
          label: Text(l.profielLopen),
        ),
      ],
      selected: {instellingen.profiel},
      onSelectionChanged: (keuze) =>
          zet(instellingen.kopie(profiel: keuze.first)),
    );
  }

  /// "Nu" of "Later": een dag in de komende week en een tijd.
  Widget _vertrek(PlannerState planner) {
    final l = AppLocalizations.of(context);
    final taal = Localizations.localeOf(context).languageCode;
    final later = planner.vertrek;
    Widget metInterceptor(BuildContext _, Widget? kind) =>
        PointerInterceptor(child: kind!);
    Future<void> kies() async {
      final nu = DateTime.now();
      final dag = await showDatePicker(
        context: context,
        firstDate: DateUtils.dateOnly(nu),
        lastDate: nu.add(const Duration(days: 7)),
        initialDate: later ?? nu,
        builder: metInterceptor,
      );
      if (dag == null || !mounted) return;
      final tijd = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(
          later ?? nu.add(const Duration(hours: 1)),
        ),
        builder: metInterceptor,
      );
      if (tijd == null || !mounted) return;
      ref
          .read(plannerProvider.notifier)
          .zetVertrek(
            DateTime(dag.year, dag.month, dag.day, tijd.hour, tijd.minute),
          );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 20),
          const SizedBox(width: 8),
          Text(l.vertrek),
          const SizedBox(width: 12),
          ChoiceChip(
            label: Text(l.vertrekNu),
            selected: later == null,
            onSelected: (_) =>
                ref.read(plannerProvider.notifier).zetVertrek(null),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(
              later == null
                  ? l.vertrekLater
                  : DateFormat('EEE d MMM HH:mm', taal).format(later),
            ),
            selected: later != null,
            onSelected: (_) => kies(),
          ),
        ],
      ),
    );
  }

  Widget _velden(PlannerState planner) {
    final l = AppLocalizations.of(context);
    final acties = ref.read(plannerProvider.notifier);
    final laatste = planner.punten.length - 1;
    // Verslepen aan de greep wisselt de volgorde. De sleutel is het id van het
    // punt, zodat elk vakje zijn eigen tekst en suggesties meeneemt.
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: planner.punten.length,
      onReorderItem: acties.verplaats,
      itemBuilder: (context, i) {
        final punt = planner.punten[i];
        return Padding(
          key: ValueKey(punt.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: Zoekveld(
            label: i == 0 ? l.van : (i == laatste ? l.naar : l.via),
            pictogram: i == 0
                ? Icons.trip_origin
                : (i == laatste ? Icons.place : Icons.more_vert),
            plaats: punt.plaats,
            nabij: widget.nabij,
            mijnLocatie: widget.mijnLocatie,
            onGekozen: (gekozen) => acties.zetPunt(i, gekozen),
            onGewist: () => acties.verwijder(i),
            voor: ReorderableDragStartListener(
              index: i,
              child: Tooltip(
                message: l.sleepOmTeVerplaatsen,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.drag_indicator),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _viaRij() {
    final l = AppLocalizations.of(context);
    final acties = ref.read(plannerProvider.notifier);
    return Row(
      children: [
        TextButton.icon(
          onPressed: acties.voegViaToe,
          icon: const Icon(Icons.add),
          label: Text(l.viaToevoegen),
        ),
        const Spacer(),
        IconButton(
          tooltip: l.omdraaien,
          onPressed: acties.draaiOm,
          icon: const Icon(Icons.swap_vert),
        ),
        IconButton(
          tooltip: l.wissen,
          onPressed: acties.naarZoeken,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  Widget _opties() {
    final l = AppLocalizations.of(context);
    final instellingen = ref.watch(instellingenProvider);
    final zet = ref.read(instellingenProvider.notifier).wijzig;
    return ExpansionTile(
      title: Text(l.opties),
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      shape: const Border(),
      children: [
        if (instellingen.profiel == Profiel.auto) ...[
          SwitchListTile(
            dense: true,
            title: Text(l.liveVerkeer),
            subtitle: Text(l.liveVerkeerUitleg),
            value: instellingen.liveVerkeer,
            onChanged: (aan) => zet(instellingen.kopie(liveVerkeer: aan)),
          ),
          SwitchListTile(
            dense: true,
            title: Text(l.vermijdSnelwegen),
            value: instellingen.vermijdSnelwegen,
            onChanged: (aan) => zet(instellingen.kopie(vermijdSnelwegen: aan)),
          ),
          SwitchListTile(
            dense: true,
            title: Text(l.vermijdTol),
            value: instellingen.vermijdTol,
            onChanged: (aan) => zet(instellingen.kopie(vermijdTol: aan)),
          ),
        ],
        SwitchListTile(
          dense: true,
          title: Text(l.vermijdVeren),
          value: instellingen.vermijdVeren,
          onChanged: (aan) => zet(instellingen.kopie(vermijdVeren: aan)),
        ),
      ],
    );
  }

  /// De routes (of wat er misging) en Start.
  Widget _uitkomst(PlannerState planner) {
    final l = AppLocalizations.of(context);
    final afsluitingen = ref.watch(afsluitingenOpRoutesProvider);
    final acties = ref.read(plannerProvider.notifier);
    return planner.routes.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(l.routeBezig),
          ],
        ),
      ),
      error: (fout, _) => _Foutmelding(fout: fout),
      data: (routes) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, route) in routes.indexed)
            _RouteKaartje(
              route: route,
              titel: i == 0 ? l.snelste : l.alternatief(i),
              gekozen: i == planner.gekozen,
              onTap: () => acties.kies(i),
              afsluitingen: afsluitingen != null && i < afsluitingen.length
                  ? afsluitingen[i]
                  : const [],
            ),
          if (planner.gekozenRoute case final route?
              when widget.onNavigeer != null) ...[
            const SizedBox(height: 8),
            _StartKnop(
              onStart: () => widget.onNavigeer!(route),
              onLocatieAan: widget.onLocatieAan,
            ),
          ],
          if (planner.gekozenRoute case final route?) ...[
            const SizedBox(height: 12),
            LangsRouteZoeker(
              // Een andere route is een nieuwe zoektocht.
              key: ObjectKey(route),
              lijn: route.punten,
              onGekozen: acties.voegViaToe,
            ),
          ],
        ],
      ),
    );
  }

  /// Hoogteprofiel en routebeschrijving van de gekozen route.
  Widget _details(PlannerState planner) {
    final l = AppLocalizations.of(context);
    final route = planner.routes.value == null ? null : planner.gekozenRoute;
    if (route == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (route.hoogtes.length > 1) ...[
          const SizedBox(height: 8),
          Text(l.hoogteprofiel, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Hoogteprofiel(hoogtes: route.hoogtes),
        ],
        const SizedBox(height: 12),
        Text(l.instructies, style: Theme.of(context).textTheme.titleSmall),
        for (final manoeuvre in route.manoeuvres)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: ManoeuvreIcoon(manoeuvre),
            title: Text(manoeuvre.instructie),
            trailing: manoeuvre.meters > 0
                ? Text(afstand(manoeuvre.meters))
                : null,
          ),
      ],
    );
  }
}

class _RouteKaartje extends StatelessWidget {
  const _RouteKaartje({
    required this.route,
    required this.titel,
    required this.gekozen,
    required this.onTap,
    this.afsluitingen = const [],
  });

  final RouteOptie route;

  /// Geplande afsluitingen op deze route (alleen bij later vertrekken).
  final List<AfsluitingOpRoute> afsluitingen;
  final String titel;
  final bool gekozen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final kleuren = Theme.of(context).colorScheme;
    final aankomst = DateTime.now().add(
      Duration(seconds: route.seconden.round()),
    );
    final taal = Localizations.localeOf(context).languageCode;
    final extra = [
      l.aankomstOm(DateFormat.Hm(taal).format(aankomst)),
      if (route.hoogtes.length > 1)
        l.stijgingDaling(route.stijging.round(), route.daling.round()),
      if (route.heeftTol) l.metTol,
      if (route.heeftVeer) l.metVeer,
    ];
    return Card(
      elevation: 0,
      color: gekozen
          ? kleuren.primaryContainer
          : kleuren.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onTap: onTap,
            title: Text('${duur(route.seconden)} · ${afstand(route.meters)}'),
            subtitle: Text([titel, ...extra].join(' · ')),
            selected: gekozen,
            trailing: _vertraging(context, route),
          ),
          if (afsluitingen.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber, size: 18, color: kleuren.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.afsluitingOpRoute(
                        _venster(context, afsluitingen.first),
                        afsluitingen.length,
                      ),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: kleuren.error),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _venster(BuildContext context, AfsluitingOpRoute venster) {
    final taal = Localizations.localeOf(context).languageCode;
    final formaat = DateFormat('EEE HH:mm', taal);
    final van = formaat.format(venster.van.toLocal());
    final tot = venster.tot;
    return tot == null ? van : '$van – ${formaat.format(tot.toLocal())}';
  }
}

/// "+9 min vertraging" rechts op het kaartje, als het verkeer er een minuut
/// of meer bij doet. Rood bij veel (tien minuten, of een kwart van de reis),
/// anders oranje.
Widget? _vertraging(BuildContext context, RouteOptie route) {
  final seconden = route.vertraging;
  if (seconden < 60) return null;
  final l = AppLocalizations.of(context);
  final veel = seconden >= 600 || seconden >= route.seconden * 0.25;
  final kleur = veel
      ? Theme.of(context).colorScheme.error
      : const Color(0xFFE65100);
  final tekst = Theme.of(context).textTheme;
  return Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        '+${duur(seconden)}',
        style: tekst.titleSmall?.copyWith(
          color: kleur,
          fontWeight: FontWeight.w600,
        ),
      ),
      Text(l.vertraging, style: tekst.bodySmall?.copyWith(color: kleur)),
    ],
  );
}

class _Foutmelding extends StatelessWidget {
  const _Foutmelding({required this.fout});

  final Object fout;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tekst = switch (fout) {
      RouteFout(code: 171) => l.geenWegInDeBuurt,
      RouteFout(code: 0) => l.serverOnbereikbaar,
      RouteFout() => l.geenRoute,
      _ => l.serverOnbereikbaar,
    };
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 12),
          Expanded(child: Text(tekst)),
        ],
      ),
    );
  }
}

/// "Start" kan pas met een bekende plek. Anders staat er waarom niet, en waar
/// het kan een knop om het te verhelpen -- nooit een knop die niets doet.
class _StartKnop extends ConsumerWidget {
  const _StartKnop({required this.onStart, this.onLocatieAan});

  final VoidCallback onStart;
  final VoidCallback? onLocatieAan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locatie = ref.watch(locatieProvider);
    final start = FilledButton.icon(
      onPressed: locatie.fix != null ? onStart : null,
      icon: locatie.stand == LocatieStand.zoekt
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.navigation),
      label: Text(
        locatie.stand == LocatieStand.zoekt
            ? l.locatieZoeken
            : l.startNavigatie,
      ),
    );
    if (locatie.fix != null || locatie.stand == LocatieStand.zoekt) {
      return start;
    }
    if (locatie.stand == LocatieStand.uit) {
      return FilledButton.tonalIcon(
        onPressed: onLocatieAan,
        icon: const Icon(Icons.my_location),
        label: Text(l.locatieAanOmTeNavigeren),
      );
    }
    final reden = locatieReden(l, locatie.stand);
    // Eenmaal geweigerd kan de vraag nog een keer; bij "nooit" en een uitgezette
    // dienst moet het via de instellingen.
    final opnieuw =
        locatie.stand == LocatieStand.geweigerd ||
        locatie.stand == LocatieStand.nietGevonden;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        start,
        if (reden != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${l.navigerenZonderLocatie} $reden',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (opnieuw && onLocatieAan != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onLocatieAan,
              child: Text(l.opnieuwProberen),
            ),
          ),
      ],
    );
  }
}
