import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/profiel.dart';
import '../providers/instellingen.dart';

extension ProfielNaam on Profiel {
  String naam(AppLocalizations l) => switch (this) {
    Profiel.auto => l.profielAuto,
    Profiel.fiets => l.profielFiets,
    Profiel.lopen => l.profielLopen,
  };

  IconData get pictogram => switch (this) {
    Profiel.auto => Icons.directions_car,
    Profiel.fiets => Icons.directions_bike,
    Profiel.lopen => Icons.directions_walk,
  };
}

/// Auto, fiets of lopen; in het routepaneel en in de instellingen.
class ProfielKeuze extends ConsumerWidget {
  const ProfielKeuze({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final instellingen = ref.watch(instellingenProvider);
    final zet = ref.read(instellingenProvider.notifier).wijzig;
    return SegmentedButton<Profiel>(
      showSelectedIcon: false,
      segments: [
        for (final profiel in Profiel.values)
          ButtonSegment(
            value: profiel,
            icon: Icon(profiel.pictogram),
            label: Text(profiel.naam(l)),
          ),
      ],
      selected: {instellingen.profiel},
      onSelectionChanged: (keuze) =>
          zet(instellingen.kopie(profiel: keuze.first)),
    );
  }
}

/// Live verkeer en wat de route mijdt. Snelwegen, tol en live verkeer gelden
/// alleen voor de auto.
class RouteOpties extends ConsumerWidget {
  const RouteOpties({super.key, this.dense = false});

  /// Klein, zoals in het routepaneel.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final instellingen = ref.watch(instellingenProvider);
    final zet = ref.read(instellingenProvider.notifier).wijzig;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (instellingen.profiel == Profiel.auto) ...[
          SwitchListTile(
            dense: dense,
            title: Text(l.liveVerkeer),
            subtitle: Text(l.liveVerkeerUitleg),
            value: instellingen.liveVerkeer,
            onChanged: (aan) => zet(instellingen.kopie(liveVerkeer: aan)),
          ),
          SwitchListTile(
            dense: dense,
            title: Text(l.vermijdSnelwegen),
            value: instellingen.vermijdSnelwegen,
            onChanged: (aan) => zet(instellingen.kopie(vermijdSnelwegen: aan)),
          ),
          SwitchListTile(
            dense: dense,
            title: Text(l.vermijdTol),
            value: instellingen.vermijdTol,
            onChanged: (aan) => zet(instellingen.kopie(vermijdTol: aan)),
          ),
        ],
        SwitchListTile(
          dense: dense,
          title: Text(l.vermijdVeren),
          value: instellingen.vermijdVeren,
          onChanged: (aan) => zet(instellingen.kopie(vermijdVeren: aan)),
        ),
      ],
    );
  }
}
