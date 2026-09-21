import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/instellingen.dart';

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
          Text(l.over, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(l.overTekst),
        ],
      ),
    );
  }
}
