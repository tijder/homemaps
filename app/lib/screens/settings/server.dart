import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/settings.dart';
import 'section.dart';

/// The address of your own HomeMaps server; Android only. On the web the
/// server is the page's own origin.
class ServerSettings extends ConsumerStatefulWidget {
  const ServerSettings({super.key});

  @override
  ConsumerState<ServerSettings> createState() => _ServerState();
}

class _ServerState extends ConsumerState<ServerSettings> {
  late final _server = TextEditingController(
    text: ref.read(settingsProvider).server,
  );
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  void _save() {
    final l = AppLocalizations.of(context);
    final text = _server.text.trim();
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.scheme.startsWith('http') ||
        uri.host.isEmpty) {
      setState(() => _error = l.serverInvalid);
      return;
    }
    setState(() => _error = null);
    ref
        .read(settingsProvider.notifier)
        .modify(ref.read(settingsProvider).copyWith(server: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.saved)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SettingsList(
      children: [
        SettingsSection(
          title: l.server,
          children: [
            SectionBlock(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _server,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      hintText: 'https://maps.example.org',
                      helperText: l.serverHelp,
                      helperMaxLines: 2,
                      errorText: _error,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(onPressed: _save, child: Text(l.save)),
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
