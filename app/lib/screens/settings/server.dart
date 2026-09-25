import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/services.dart';
import '../../providers/settings.dart';
import '../../services/server_check.dart';
import 'section.dart';

/// The address of your own HomeMaps server; not on the web, where the server
/// is the page's own origin. While typing it says whether the server works.
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
  Timer? _debounce;
  CancelToken? _inFlight;

  /// The address being checked or last checked, and the answer (null while
  /// checking).
  String? _checking;
  ServerCheck? _check;

  @override
  void initState() {
    super.initState();
    if (_server.text.isNotEmpty) _checkNow(_server.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _inFlight?.cancel();
    _server.dispose();
    super.dispose();
  }

  void _typed(String text) {
    _debounce?.cancel();
    _inFlight?.cancel();
    setState(() {
      _error = null;
      _checking = null;
      _check = null;
    });
    // Not on every key: only after a short pause.
    _debounce = Timer(const Duration(milliseconds: 700), () => _checkNow(text));
  }

  Future<void> _checkNow(String text) async {
    final address = normalizeServer(text);
    _inFlight?.cancel();
    if (address == null) return;
    final cancel = _inFlight = CancelToken();
    setState(() {
      _checking = address;
      _check = null;
    });
    final check = await checkServer(
      ref.read(dioProvider),
      address,
      cancel: cancel,
    );
    if (mounted && !cancel.isCancelled && _checking == address) {
      setState(() => _check = check);
    }
  }

  void _save() {
    final l = AppLocalizations.of(context);
    final address = normalizeServer(_server.text);
    if (address == null) {
      setState(() => _error = l.serverInvalid);
      return;
    }
    _debounce?.cancel();
    _server.text = address;
    setState(() => _error = null);
    ref
        .read(settingsProvider.notifier)
        .modify(ref.read(settingsProvider).copyWith(server: address));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.saved)));
    if (_checking != address) _checkNow(address);
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
                    onChanged: _typed,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      hintText: 'https://maps.example.org',
                      helperText: l.serverHelp,
                      helperMaxLines: 2,
                      errorText: _error,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (_checking != null) ...[
                    const SizedBox(height: 12),
                    _CheckStatus(_check),
                  ],
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

/// One line on how the server is doing; [check] null while checking.
class _CheckStatus extends StatelessWidget {
  const _CheckStatus(this.check);

  final ServerCheck? check;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    String name(ServerPart part) => switch (part) {
      ServerPart.map => l.serverPartMap,
      ServerPart.search => l.serverPartSearch,
      ServerPart.routes => l.serverPartRoutes,
    };
    final check = this.check;
    final (Widget icon, String text) = switch (check) {
      null => (
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        l.serverChecking,
      ),
      ServerCheck(works: true) => (
        Icon(Icons.check_circle, color: colors.primary),
        l.serverWorks,
      ),
      ServerCheck(unreachable: true) => (
        Icon(Icons.error, color: colors.error),
        l.serverUnreachable,
      ),
      _ => (
        Icon(Icons.warning_amber, color: colors.error),
        l.serverPartlyWorks(check.failing.map(name).join(', ')),
      ),
    };
    return Row(
      children: [
        icon,
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    );
  }
}
