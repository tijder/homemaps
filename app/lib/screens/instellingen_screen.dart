import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/instellingen.dart';
import '../providers/plekken.dart';

@RoutePage()
class InstellingenScreen extends ConsumerStatefulWidget {
  const InstellingenScreen({super.key});

  @override
  ConsumerState<InstellingenScreen> createState() => _InstellingenScreenState();
}

class _InstellingenScreenState extends ConsumerState<InstellingenScreen> {
  late final _server = TextEditingController(
    text: ref.read(instellingenProvider).server,
  );
  String? _fout;

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  void _bewaar() {
    final l = AppLocalizations.of(context);
    final tekst = _server.text.trim();
    final uri = Uri.tryParse(tekst);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.scheme.startsWith('http') ||
        uri.host.isEmpty) {
      setState(() => _fout = l.serverOngeldig);
      return;
    }
    ref
        .read(instellingenProvider.notifier)
        .wijzig(ref.read(instellingenProvider).kopie(server: tekst));
    context.router.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.instellingen)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Op het web is de server de eigen origin; daar valt niets in te stellen.
          if (!kIsWeb) ...[
            Text(l.server, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _server,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onSubmitted: (_) => _bewaar(),
              decoration: InputDecoration(
                hintText: 'https://maps.example.org',
                helperText: l.serverUitleg,
                helperMaxLines: 2,
                errorText: _fout,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _bewaar, child: Text(l.opslaan)),
            ),
            const Divider(height: 32),
          ],
          _Plekken(),
          const Divider(height: 32),
          Text(l.over, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l.overTekst),
        ],
      ),
    );
  }
}

/// Thuis en werk bekijken en weghalen, en de recente plekken wissen. Instellen
/// gebeurt op het kaartje van een gevonden plek.
class _Plekken extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final plekken = ref.watch(plekkenProvider);
    final acties = ref.read(plekkenProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.plekken, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l.plekkenUitleg, style: Theme.of(context).textTheme.bodySmall),
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
            contentPadding: EdgeInsets.zero,
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
        ListTile(
          contentPadding: EdgeInsets.zero,
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
    );
  }
}
