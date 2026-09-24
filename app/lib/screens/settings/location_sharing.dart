import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/location_sharing.dart';
import '../../providers/dawarich.dart';
import '../../providers/location.dart';
import '../../providers/location_sharing.dart';
import '../../services/location_sharer.dart';
import 'section.dart';

/// Where and how the position is shared while navigating, as in Colota:
/// choose a server, the address, authentication and the fields.
class LocationSharingSettings extends ConsumerStatefulWidget {
  const LocationSharingSettings({super.key});

  @override
  ConsumerState<LocationSharingSettings> createState() =>
      _LocationSharingState();
}

class _LocationSharingState extends ConsumerState<LocationSharingSettings> {
  late ShareSettings _draft;
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _secret = TextEditingController();
  final _fieldNames = TextEditingController();
  final _extra = TextEditingController();
  final _interval = TextEditingController();
  final _distance = TextEditingController();
  String? _urlError;
  String? _testResult;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _fill(ref.read(shareSettingsProvider));
    // The secret only comes out of secure storage once that has been read.
    ref.read(shareSettingsProvider.notifier).loaded.then((_) {
      if (mounted) _secret.text = ref.read(shareSettingsProvider).secret;
    });
  }

  @override
  void dispose() {
    for (final c in [
      _url,
      _username,
      _secret,
      _fieldNames,
      _extra,
      _interval,
      _distance,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(ShareSettings i) {
    _draft = i;
    _url.text = i.url;
    _username.text = i.username;
    _secret.text = i.secret;
    _fieldNames.text = _toLines(i.fieldNames);
    _extra.text = _toLines(i.extraFields);
    _interval.text = '${i.interval}';
    _distance.text = '${i.minDistance}';
  }

  static String _toLines(Map<String, String> fields) =>
      [for (final e in fields.entries) '${e.key}=${e.value}'].join('\n');

  static Map<String, String> _parseLines(String text) => {
    for (final line in const LineSplitter().convert(text))
      if (line.contains('='))
        line.substring(0, line.indexOf('=')).trim(): line
            .substring(line.indexOf('=') + 1)
            .trim(),
  };

  /// What's on the screen right now.
  ShareSettings get _current => _draft.copyWith(
    url: _url.text.trim(),
    username: _username.text.trim(),
    secret: _secret.text,
    fieldNames: _parseLines(_fieldNames.text),
    extraFields: _parseLines(_extra.text),
    interval: int.tryParse(_interval.text)?.clamp(1, 3600),
    minDistance: int.tryParse(_distance.text)?.clamp(0, 10000),
  );

  bool _check(ShareSettings i) {
    final correct = i.complete;
    setState(
      () => _urlError = correct
          ? null
          : AppLocalizations.of(context).shareUrlInvalid,
    );
    return correct;
  }

  Future<void> _save() async {
    // Otherwise a still-empty field overwrites the saved secret.
    await ref.read(shareSettingsProvider.notifier).loaded;
    final newValue = _current;
    if (newValue.enabled && !_check(newValue)) return;
    await ref.read(shareSettingsProvider.notifier).modify(newValue);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).saved)));
  }

  Future<void> _turnOn(bool enabled) async {
    await ref.read(shareSettingsProvider.notifier).loaded;
    final newValue = _current.copyWith(enabled: enabled);
    if (enabled && !_check(newValue)) return;
    setState(() => _draft = newValue);
    await ref.read(shareSettingsProvider.notifier).modify(newValue);
  }

  /// The point for the test and the example: where you are, or the Dom tower.
  SharedPoint _examplePoint() {
    final fix = ref.read(locationProvider).fix;
    return SharedPoint(
      lat: fix?.point.latitude ?? 52.0907,
      lon: fix?.point.longitude ?? 5.1214,
      tst: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      acc: fix?.accuracy ?? 5,
      vel: fix?.speed ?? 0,
      bear: fix?.heading ?? 0,
    );
  }

  Future<void> _testConnection() async {
    final l = AppLocalizations.of(context);
    final now = _current;
    if (!_check(now)) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final error = await ref
        .read(locationSharerProvider.notifier)
        .test(now, _examplePoint());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = error == null
          ? l.shareTestSucceeded
          : l.shareTestFailed(error);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = ref.watch(locationSharerProvider);
    final now = _current;
    InputDecoration field(String label, {String? hint, String? help}) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: help,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        );
    Widget label(String title) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title, style: text.labelLarge),
    );

    return SettingsList(
      children: [
        SettingsSection(
          help: [
            l.locationSharingHelp,
            if (sharesViaDawarich(now, ref.watch(dawarichProvider)))
              l.shareViaDawarich,
          ].join(' '),
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.share_location),
              title: Text(l.locationSharingEnabled),
              value: _draft.enabled,
              onChanged: _turnOn,
            ),
          ],
        ),
        SettingsSection(
          title: l.shareServer,
          children: [
            RadioGroup<ShareTemplate>(
              groupValue: _draft.template,
              onChanged: (s) {
                if (s == null) return;
                setState(() {
                  _draft = _current.withTemplate(s);
                  _extra.text = _toLines(_draft.extraFields);
                });
              },
              child: Column(
                children: [
                  for (final s in ShareTemplate.values)
                    RadioListTile<ShareTemplate>(
                      value: s,
                      title: Text(s.label ?? l.shareCustom),
                      subtitle: Text(l.shareTemplateHelp(s.name)),
                    ),
                ],
              ),
            ),
          ],
        ),
        SettingsSection(
          title: l.shareConnection,
          children: [
            SectionBlock(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    onChanged: (_) => setState(() {}),
                    decoration: field(
                      l.shareUrl,
                      hint: _draft.template.exampleUrl,
                      help: kIsWeb ? l.shareUrlWeb : null,
                    ).copyWith(errorText: _urlError),
                  ),
                  if (_draft.template.methodChoosable) ...[
                    label(l.shareMethod),
                    SegmentedButton<ShareMethod>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ShareMethod.post,
                          label: Text('POST'),
                        ),
                        ButtonSegment(
                          value: ShareMethod.get,
                          label: Text('GET'),
                        ),
                      ],
                      selected: {_draft.method},
                      onSelectionChanged: (choice) => setState(
                        () => _draft = _current.copyWith(method: choice.first),
                      ),
                    ),
                  ],
                  label(l.shareAuth),
                  SegmentedButton<ShareAuth>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ShareAuth.none,
                        label: Text(l.shareAuthNone),
                      ),
                      const ButtonSegment(
                        value: ShareAuth.basic,
                        label: Text('Basic'),
                      ),
                      const ButtonSegment(
                        value: ShareAuth.bearer,
                        label: Text('Bearer'),
                      ),
                    ],
                    selected: {_draft.auth},
                    onSelectionChanged: (choice) => setState(
                      () => _draft = _current.copyWith(auth: choice.first),
                    ),
                  ),
                  if (_draft.auth == ShareAuth.basic) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _username,
                      autocorrect: false,
                      decoration: field(l.shareUsername),
                    ),
                  ],
                  if (_draft.auth != ShareAuth.none) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _secret,
                      obscureText: true,
                      autocorrect: false,
                      decoration: field(
                        _draft.auth == ShareAuth.basic
                            ? l.sharePassword
                            : l.shareToken,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        SettingsSection(
          title: l.sharePoints,
          children: [
            SectionBlock(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_draft.template == ShareTemplate.custom) ...[
                    TextField(
                      controller: _fieldNames,
                      maxLines: null,
                      autocorrect: false,
                      onChanged: (_) => setState(() {}),
                      decoration: field(
                        l.shareFieldNames,
                        hint: 'lat=latitude\nlon=longitude',
                        help: l.shareFieldNamesHelp,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _extra,
                    maxLines: null,
                    autocorrect: false,
                    onChanged: (_) => setState(() {}),
                    decoration: field(
                      l.shareExtraFields,
                      help: l.shareExtraFieldsHelp,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _interval,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: field(l.shareInterval),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _distance,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: field(l.shareMinDistance),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsSection(
          title: l.shareStatus,
          children: [
            SectionBlock(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.lastSent == null
                        ? l.shareNothingYet
                        : l.shareLastSent(
                            DateFormat.Hms(l.localeName)
                                .format(status.lastSent!),
                          ),
                  ),
                  Text(l.shareQueued(status.queued)),
                  if (status.error case final error?)
                    Text(
                      l.shareError(error),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (status.stopped) Text(l.shareStopped),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _testing ? null : _testConnection,
                        icon: _testing
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.wifi_tethering),
                        label: Text(l.shareTest),
                      ),
                      if (status.queued > 0)
                        TextButton(
                          onPressed: () => ref
                              .read(locationSharerProvider.notifier)
                              .clearQueue(),
                          child: Text(l.shareClearQueue),
                        ),
                    ],
                  ),
                  if (_testResult case final outcome?) ...[
                    const SizedBox(height: 8),
                    Text(outcome),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (now.complete)
          SettingsSection(
            title: l.shareExample,
            children: [
              _Example(buildRequest(now, [_examplePoint()])),
            ],
          ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: _save, child: Text(l.save)),
        ),
      ],
    );
  }
}

/// What goes to the server, as Colota shows it too. Without the secret: that
/// doesn't need to be on screen.
class _Example extends StatelessWidget {
  const _Example(this.request);

  final ShareRequest request;

  @override
  Widget build(BuildContext context) {
    final body = request.body;
    final text = [
      '${request.method.name.toUpperCase()} ${request.uri}',
      if (request.headers.containsKey('Authorization'))
        'Authorization: ${request.headers['Authorization']!.split(' ').first} …',
      if (body != null) const JsonEncoder.withIndent('  ').convert(body),
    ].join('\n');
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}
