import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/instellingen.dart';
import 'sectie.dart';

/// Hoe de kaart eruitziet; dezelfde keuzes als in het lagenmenu op de kaart.
class KaartInstellingen extends ConsumerWidget {
  const KaartInstellingen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final instellingen = ref.watch(instellingenProvider);
    final zet = ref.read(instellingenProvider.notifier).wijzig;
    final stijl = KaartStijl.van(instellingen.stijl);
    return InstellingenLijst(
      children: [
        InstellingenSectie(
          titel: l.kaartstijl,
          children: [
            SectieBlok(
              child: SegmentedButton<KaartStijl>(
                showSelectedIcon: false,
                segments: [
                  for (final s in KaartStijl.values)
                    ButtonSegment(value: s, label: Text(s.naam(l))),
                ],
                selected: {stijl},
                onSelectionChanged: (keuze) =>
                    zet(instellingen.kopie(stijl: keuze.first.id)),
              ),
            ),
          ],
        ),
        InstellingenSectie(
          titel: l.dagEnNacht,
          uitleg: l.themaAlleenKaart,
          children: [
            SectieBlok(
              child: SegmentedButton<KaartThema>(
                showSelectedIcon: false,
                segments: [
                  for (final t in KaartThema.values)
                    ButtonSegment(value: t, label: Text(t.naam(l))),
                ],
                selected: {instellingen.thema},
                onSelectionChanged: stijl == KaartStijl.kaart
                    ? (keuze) => zet(instellingen.kopie(thema: keuze.first))
                    : null,
              ),
            ),
          ],
        ),
        InstellingenSectie(
          titel: l.lagen,
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.traffic_outlined),
              title: Text(l.verkeerOpKaart),
              subtitle: Text(l.verkeerOpKaartUitleg),
              value: instellingen.verkeerOpKaart,
              onChanged: (aan) => zet(instellingen.kopie(verkeerOpKaart: aan)),
            ),
          ],
        ),
      ],
    );
  }
}
