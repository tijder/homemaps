import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/plekken.dart';
import 'sectie.dart';

/// Thuis en werk bekijken en weghalen, en de recente plekken wissen. Instellen
/// gebeurt op het kaartje van een gevonden plek.
class PlekkenInstellingen extends ConsumerWidget {
  const PlekkenInstellingen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final plekken = ref.watch(plekkenProvider);
    final acties = ref.read(plekkenProvider.notifier);
    return InstellingenLijst(
      children: [
        InstellingenSectie(
          titel: l.plekken,
          uitleg: l.plekkenUitleg,
          children: [
            for (final (pictogram, label, plaats, wis) in [
              (
                Icons.home_outlined,
                l.thuis,
                plekken.thuis,
                () => acties.zetThuis(null),
              ),
              (
                Icons.work_outline,
                l.werk,
                plekken.werk,
                () => acties.zetWerk(null),
              ),
            ])
              ListTile(
                leading: Icon(pictogram),
                title: Text(label),
                subtitle: Text(plaats?.naam ?? l.nietIngesteld),
                trailing: plaats == null
                    ? null
                    : IconButton(
                        tooltip: l.verwijderen,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: wis,
                      ),
              ),
          ],
        ),
        InstellingenSectie(
          children: [
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(l.recentePlekken),
              subtitle: Text(l.aantalPlekken(plekken.recent.length)),
              trailing: plekken.recent.isEmpty
                  ? null
                  : TextButton(
                      onPressed: acties.wisRecent,
                      child: Text(l.wissenKort),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
