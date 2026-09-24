import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/instellingen.dart';
import 'sectie.dart';

/// Het adres van de eigen HomeMaps-server; alleen op Android. Op het web is de
/// server de eigen origin.
class ServerInstellingen extends ConsumerStatefulWidget {
  const ServerInstellingen({super.key});

  @override
  ConsumerState<ServerInstellingen> createState() => _ServerState();
}

class _ServerState extends ConsumerState<ServerInstellingen> {
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
    setState(() => _fout = null);
    ref
        .read(instellingenProvider.notifier)
        .wijzig(ref.read(instellingenProvider).kopie(server: tekst));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.opgeslagen)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return InstellingenLijst(
      children: [
        InstellingenSectie(
          titel: l.server,
          children: [
            SectieBlok(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                    child: FilledButton(
                      onPressed: _bewaar,
                      child: Text(l.opslaan),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
