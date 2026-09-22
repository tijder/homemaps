import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../l10n/app_localizations.dart';
import '../models/plaats.dart';
import '../models/profiel.dart';
import '../models/route.dart';
import '../providers/instellingen.dart';
import '../providers/planner.dart';
import '../services/valhalla_service.dart';
import '../utils/opmaak.dart';
import 'hoogteprofiel.dart';
import 'zoekveld.dart';

/// Het paneel naast (breed scherm) of onder (smal scherm) de kaart: de punten,
/// de vervoerswijze, de opties en de uitkomst.
class RoutePaneel extends ConsumerWidget {
  const RoutePaneel({
    super.key,
    required this.nabij,
    this.mijnLocatie,
    this.scroll,
  });

  final LatLng? Function() nabij;

  /// Zie [Zoekveld.mijnLocatie].
  final Future<Plaats?> Function()? mijnLocatie;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final planner = ref.watch(plannerProvider);
    final acties = ref.read(plannerProvider.notifier);
    final instellingen = ref.watch(instellingenProvider);
    final zet = ref.read(instellingenProvider.notifier).wijzig;
    final laatste = planner.punten.length - 1;

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l.terugNaarZoeken,
              onPressed: acties.naarZoeken,
              icon: const Icon(Icons.arrow_back),
            ),
            Text(l.route, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        SegmentedButton<Profiel>(
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
        ),
        const SizedBox(height: 12),
        // Verslepen aan de greep wisselt de volgorde. De sleutel is het id van het
        // punt, zodat elk vakje zijn eigen tekst en suggesties meeneemt.
        ReorderableListView.builder(
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
                nabij: nabij,
                mijnLocatie: mijnLocatie,
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
        ),
        Row(
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
        ),
        ExpansionTile(
          title: Text(l.opties),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          shape: const Border(),
          children: [
            if (instellingen.profiel == Profiel.auto)
              SwitchListTile(
                dense: true,
                title: Text(l.liveVerkeer),
                subtitle: Text(l.liveVerkeerUitleg),
                value: instellingen.liveVerkeer,
                onChanged: (aan) => zet(instellingen.kopie(liveVerkeer: aan)),
              ),
            if (instellingen.profiel == Profiel.auto) ...[
              SwitchListTile(
                dense: true,
                title: Text(l.vermijdSnelwegen),
                value: instellingen.vermijdSnelwegen,
                onChanged: (aan) =>
                    zet(instellingen.kopie(vermijdSnelwegen: aan)),
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
        ),
        const Divider(),
        planner.routes.when(
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
                ),
              if (planner.gekozenRoute case final route?) ...[
                if (route.hoogtes.length > 1) ...[
                  const SizedBox(height: 8),
                  Text(
                    l.hoogteprofiel,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Hoogteprofiel(hoogtes: route.hoogtes),
                ],
                const SizedBox(height: 12),
                Text(
                  l.instructies,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final manoeuvre in route.manoeuvres)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_pictogram(manoeuvre.type)),
                    title: Text(manoeuvre.instructie),
                    trailing: manoeuvre.meters > 0
                        ? Text(afstand(manoeuvre.meters))
                        : null,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Valhalla's manoeuvretypes, gegroepeerd naar wat de pijl moet tonen.
  static IconData _pictogram(int type) => switch (type) {
    1 || 2 || 3 => Icons.trip_origin,
    4 || 5 || 6 => Icons.place,
    9 || 10 || 11 || 18 || 20 || 23 => Icons.turn_right,
    14 || 15 || 16 || 19 || 21 || 24 => Icons.turn_left,
    12 || 13 => Icons.u_turn_left,
    26 || 27 => Icons.roundabout_right,
    28 || 29 => Icons.directions_boat,
    _ => Icons.straight,
  };
}

class _RouteKaartje extends StatelessWidget {
  const _RouteKaartje({
    required this.route,
    required this.titel,
    required this.gekozen,
    required this.onTap,
  });

  final RouteOptie route;
  final String titel;
  final bool gekozen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final kleuren = Theme.of(context).colorScheme;
    final extra = [
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
      child: ListTile(
        onTap: onTap,
        title: Text('${duur(route.seconden)} · ${afstand(route.meters)}'),
        subtitle: Text([titel, ...extra].join(' · ')),
        selected: gekozen,
      ),
    );
  }
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
