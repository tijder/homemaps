import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/locatie_delen.dart';
import '../providers/dawarich.dart';
import '../providers/locatie.dart';
import '../providers/locatie_delen.dart';
import '../services/locatie_deler.dart';

/// Waar en hoe de positie tijdens het navigeren gedeeld wordt, zoals in
/// Colota: een server kiezen, het adres, inloggen en de velden.
@RoutePage()
class LocatieDelenScreen extends ConsumerStatefulWidget {
  const LocatieDelenScreen({super.key});

  @override
  ConsumerState<LocatieDelenScreen> createState() => _LocatieDelenState();
}

class _LocatieDelenState extends ConsumerState<LocatieDelenScreen> {
  late DeelInstellingen _concept;
  final _url = TextEditingController();
  final _gebruiker = TextEditingController();
  final _geheim = TextEditingController();
  final _veldnamen = TextEditingController();
  final _extra = TextEditingController();
  final _interval = TextEditingController();
  final _afstand = TextEditingController();
  String? _urlFout;
  String? _testUitslag;
  bool _test = false;

  @override
  void initState() {
    super.initState();
    _vul(ref.read(deelInstellingenProvider));
    // Het geheim komt pas uit de veilige opslag als die gelezen is.
    ref.read(deelInstellingenProvider.notifier).geladen.then((_) {
      if (mounted) _geheim.text = ref.read(deelInstellingenProvider).geheim;
    });
  }

  @override
  void dispose() {
    for (final c in [
      _url,
      _gebruiker,
      _geheim,
      _veldnamen,
      _extra,
      _interval,
      _afstand,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _vul(DeelInstellingen i) {
    _concept = i;
    _url.text = i.url;
    _gebruiker.text = i.gebruiker;
    _geheim.text = i.geheim;
    _veldnamen.text = _regels(i.veldnamen);
    _extra.text = _regels(i.extraVelden);
    _interval.text = '${i.interval}';
    _afstand.text = '${i.minAfstand}';
  }

  static String _regels(Map<String, String> velden) =>
      [for (final e in velden.entries) '${e.key}=${e.value}'].join('\n');

  static Map<String, String> _leesRegels(String tekst) => {
    for (final regel in const LineSplitter().convert(tekst))
      if (regel.contains('='))
        regel.substring(0, regel.indexOf('=')).trim(): regel
            .substring(regel.indexOf('=') + 1)
            .trim(),
  };

  /// Wat er nu op het scherm staat.
  DeelInstellingen get _nu => _concept.kopie(
    url: _url.text.trim(),
    gebruiker: _gebruiker.text.trim(),
    geheim: _geheim.text,
    veldnamen: _leesRegels(_veldnamen.text),
    extraVelden: _leesRegels(_extra.text),
    interval: int.tryParse(_interval.text)?.clamp(1, 3600),
    minAfstand: int.tryParse(_afstand.text)?.clamp(0, 10000),
  );

  bool _controleer(DeelInstellingen i) {
    final goed = i.compleet;
    setState(
      () =>
          _urlFout = goed ? null : AppLocalizations.of(context).deelUrlOngeldig,
    );
    return goed;
  }

  Future<void> _bewaar() async {
    // Anders overschrijft een nog leeg veld het bewaarde geheim.
    await ref.read(deelInstellingenProvider.notifier).geladen;
    final nieuw = _nu;
    if (nieuw.aan && !_controleer(nieuw)) return;
    await ref.read(deelInstellingenProvider.notifier).wijzig(nieuw);
    if (mounted) context.router.maybePop();
  }

  Future<void> _zetAan(bool aan) async {
    await ref.read(deelInstellingenProvider.notifier).geladen;
    final nieuw = _nu.kopie(aan: aan);
    if (aan && !_controleer(nieuw)) return;
    setState(() => _concept = nieuw);
    await ref.read(deelInstellingenProvider.notifier).wijzig(nieuw);
  }

  /// Het punt voor de test en het voorbeeld: waar je bent, of de Dom.
  DeelPunt _voorbeeldPunt() {
    final fix = ref.read(locatieProvider).fix;
    return DeelPunt(
      lat: fix?.punt.latitude ?? 52.0907,
      lon: fix?.punt.longitude ?? 5.1214,
      tst: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      acc: fix?.nauwkeurigheid ?? 5,
      vel: fix?.snelheid ?? 0,
      bear: fix?.koers ?? 0,
    );
  }

  Future<void> _testVerbinding() async {
    final l = AppLocalizations.of(context);
    final nu = _nu;
    if (!_controleer(nu)) return;
    setState(() {
      _test = true;
      _testUitslag = null;
    });
    final fout = await ref
        .read(locatieDelerProvider.notifier)
        .test(nu, _voorbeeldPunt());
    if (!mounted) return;
    setState(() {
      _test = false;
      _testUitslag = fout == null ? l.deelTestGelukt : l.deelTestMislukt(fout);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tekst = Theme.of(context).textTheme;
    final status = ref.watch(locatieDelerProvider);
    final nu = _nu;
    Widget kop(String titel) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(titel, style: tekst.titleMedium),
    );
    InputDecoration veld(String label, {String? hint, String? uitleg}) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: uitleg,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(l.locatieDelen),
        actions: [TextButton(onPressed: _bewaar, child: Text(l.opslaan))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.locatieDelenUitleg),
          if (deeltViaDawarich(nu, ref.watch(dawarichProvider))) ...[
            const SizedBox(height: 8),
            Text(l.deelViaDawarich, style: tekst.bodySmall),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.locatieDelenAan),
            value: _concept.aan,
            onChanged: _zetAan,
          ),
          kop(l.deelServer),
          RadioGroup<DeelSjabloon>(
            groupValue: _concept.sjabloon,
            onChanged: (s) {
              if (s == null) return;
              setState(() {
                _concept = _nu.metSjabloon(s);
                _extra.text = _regels(_concept.extraVelden);
              });
            },
            child: Column(
              children: [
                for (final s in DeelSjabloon.values)
                  RadioListTile<DeelSjabloon>(
                    contentPadding: EdgeInsets.zero,
                    value: s,
                    title: Text(s.naam ?? l.deelAangepast),
                    subtitle: Text(l.deelSjabloonUitleg(s.name)),
                  ),
              ],
            ),
          ),
          kop(l.deelUrl),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: veld(
              l.deelUrl,
              hint: _concept.sjabloon.voorbeeldUrl,
              uitleg: kIsWeb ? l.deelUrlWeb : null,
            ).copyWith(errorText: _urlFout),
          ),
          if (_concept.sjabloon.methodeKiesbaar) ...[
            kop(l.deelMethode),
            SegmentedButton<DeelMethode>(
              segments: const [
                ButtonSegment(value: DeelMethode.post, label: Text('POST')),
                ButtonSegment(value: DeelMethode.get, label: Text('GET')),
              ],
              selected: {_concept.methode},
              onSelectionChanged: (keuze) =>
                  setState(() => _concept = _nu.kopie(methode: keuze.first)),
            ),
          ],
          kop(l.deelInlog),
          SegmentedButton<DeelInlog>(
            segments: [
              ButtonSegment(
                value: DeelInlog.geen,
                label: Text(l.deelInlogGeen),
              ),
              const ButtonSegment(value: DeelInlog.basic, label: Text('Basic')),
              const ButtonSegment(
                value: DeelInlog.bearer,
                label: Text('Bearer'),
              ),
            ],
            selected: {_concept.inlog},
            onSelectionChanged: (keuze) =>
                setState(() => _concept = _nu.kopie(inlog: keuze.first)),
          ),
          if (_concept.inlog == DeelInlog.basic) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _gebruiker,
              autocorrect: false,
              decoration: veld(l.deelGebruiker),
            ),
          ],
          if (_concept.inlog != DeelInlog.geen) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _geheim,
              obscureText: true,
              autocorrect: false,
              decoration: veld(
                _concept.inlog == DeelInlog.basic
                    ? l.deelWachtwoord
                    : l.deelToken,
              ),
            ),
          ],
          if (_concept.sjabloon == DeelSjabloon.aangepast) ...[
            kop(l.deelVeldnamen),
            TextField(
              controller: _veldnamen,
              maxLines: null,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              decoration: veld(
                l.deelVeldnamen,
                hint: 'lat=latitude\nlon=longitude',
                uitleg: l.deelVeldnamenUitleg,
              ),
            ),
          ],
          kop(l.deelExtraVelden),
          TextField(
            controller: _extra,
            maxLines: null,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: veld(
              l.deelExtraVelden,
              uitleg: l.deelExtraVeldenUitleg,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _interval,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: veld(l.deelInterval),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _afstand,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: veld(l.deelMinAfstand),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _test ? null : _testVerbinding,
                icon: _test
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: Text(l.deelTesten),
              ),
            ],
          ),
          if (_testUitslag case final uitslag?) ...[
            const SizedBox(height: 8),
            Text(uitslag),
          ],
          kop(l.deelStatus),
          Text(
            status.laatstVerstuurd == null
                ? l.deelNogNiets
                : l.deelLaatst(
                    DateFormat.Hms(l.localeName)
                        .format(status.laatstVerstuurd!),
                  ),
          ),
          Text(l.deelInWachtrij(status.inWachtrij)),
          if (status.fout case final fout?)
            Text(
              l.deelFout(fout),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (status.gestopt) Text(l.deelGestopt),
          if (status.inWachtrij > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    ref.read(locatieDelerProvider.notifier).wisWachtrij(),
                child: Text(l.deelWisWachtrij),
              ),
            ),
          if (nu.compleet) ...[
            kop(l.deelVoorbeeld),
            _Voorbeeld(bouwVerzoek(nu, [_voorbeeldPunt()])),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: _bewaar, child: Text(l.opslaan)),
          ),
        ],
      ),
    );
  }
}

/// Wat er naar de server gaat, zoals Colota het ook laat zien. Zonder het
/// geheim: dat hoeft niet op het scherm.
class _Voorbeeld extends StatelessWidget {
  const _Voorbeeld(this.verzoek);

  final DeelVerzoek verzoek;

  @override
  Widget build(BuildContext context) {
    final body = verzoek.body;
    final tekst = [
      '${verzoek.methode.name.toUpperCase()} ${verzoek.uri}',
      if (verzoek.headers.containsKey('Authorization'))
        'Authorization: ${verzoek.headers['Authorization']!.split(' ').first} …',
      if (body != null) const JsonEncoder.withIndent('  ').convert(body),
    ].join('\n');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        tekst,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}
