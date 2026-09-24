import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/dawarich.dart';
import '../../providers/dawarich.dart';
import '../../providers/locatie_delen.dart';
import '../../services/dawarich_service.dart';
import 'sectie.dart';

/// Een [DawarichFout] als zin voor op het scherm.
String dawarichFoutTekst(AppLocalizations l, Object fout) => switch (fout) {
  DawarichFout(soort: DawarichFoutSoort.inlog) => l.dawarichFoutInlog,
  DawarichFout(soort: DawarichFoutSoort.wachtwoordUit) =>
    l.dawarichFoutWachtwoordUit,
  DawarichFout(soort: DawarichFoutSoort.geblokkeerd) =>
    l.dawarichFoutGeblokkeerd,
  DawarichFout(soort: DawarichFoutSoort.geenFamilie) => l.dawarichGeenFamilie,
  DawarichFout(soort: DawarichFoutSoort.geenAbonnement) =>
    l.dawarichGeenAbonnement,
  DawarichFout(soort: DawarichFoutSoort.verbinding, :final detail) =>
    l.dawarichFoutVerbinding(detail ?? ''),
  DawarichFout(:final detail) => l.dawarichFoutOnbekend(detail ?? ''),
  _ => l.dawarichFoutOnbekend('$fout'),
};

/// Inloggen bij Dawarich, en daarna: familie delen, delen tijdens het
/// navigeren en de familie op de kaart.
class DawarichInstellingen extends ConsumerWidget {
  const DawarichInstellingen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(dawarichProvider);
    return account == null ? const _Inloggen() : _Ingelogd(account);
  }
}

class _Inloggen extends ConsumerStatefulWidget {
  const _Inloggen();

  @override
  ConsumerState<_Inloggen> createState() => _InloggenState();
}

class _InloggenState extends ConsumerState<_Inloggen> {
  final _server = TextEditingController();
  final _email = TextEditingController();
  final _wachtwoord = TextEditingController();
  final _sleutel = TextEditingController();
  bool _metSleutel = false;
  bool _bezig = false;
  String? _serverFout;
  String? _fout;

  @override
  void dispose() {
    for (final c in [_server, _email, _wachtwoord, _sleutel]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _inloggen() async {
    final l = AppLocalizations.of(context);
    final server = DawarichService.normaliseer(_server.text);
    setState(() {
      _serverFout = server == null ? l.serverOngeldig : null;
      _fout = null;
    });
    if (server == null) return;
    setState(() => _bezig = true);
    final notifier = ref.read(dawarichProvider.notifier);
    try {
      if (_metSleutel) {
        await notifier.metSleutel(server, _sleutel.text);
      } else {
        final uitslag = await notifier.inloggen(
          server,
          _email.text,
          _wachtwoord.text,
        );
        if (uitslag is DawarichTweeStap) {
          final code = await _vraagCode();
          if (code == null || code.trim().isEmpty) return;
          await notifier.bevestig(server, uitslag.token, code);
        }
      }
    } on DawarichFout catch (fout) {
      if (mounted) setState(() => _fout = dawarichFoutTekst(l, fout));
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }

  Future<String?> _vraagCode() {
    final code = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l.dawarichCode),
          content: TextField(
            controller: code,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            onSubmitted: (tekst) => Navigator.pop(context, tekst),
            decoration: InputDecoration(helperText: l.dawarichCodeUitleg),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.annuleren),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, code.text),
              child: Text(l.dawarichBevestig),
            ),
          ],
        );
      },
    ).whenComplete(code.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    InputDecoration veld(String label, {String? hint, String? uitleg}) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: uitleg,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        );
    return AutofillGroup(
      child: InstellingenLijst(
        children: [
          InstellingenSectie(
            uitleg: l.dawarichUitleg,
            children: [
              SectieBlok(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: veld(
                        l.dawarichServer,
                        hint: 'https://dawarich.example',
                        uitleg: kIsWeb ? l.dawarichWeb : null,
                      ).copyWith(errorText: _serverFout),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(l.dawarichMetWachtwoord),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(l.dawarichMetSleutel),
                        ),
                      ],
                      selected: {_metSleutel},
                      onSelectionChanged: (keuze) =>
                          setState(() => _metSleutel = keuze.first),
                    ),
                    const SizedBox(height: 16),
                    if (_metSleutel)
                      TextField(
                        controller: _sleutel,
                        obscureText: true,
                        autocorrect: false,
                        onSubmitted: (_) => _inloggen(),
                        decoration: veld(
                          l.dawarichSleutel,
                          uitleg: l.dawarichSleutelUitleg,
                        ),
                      )
                    else ...[
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        decoration: veld(l.dawarichEmail),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _wachtwoord,
                        obscureText: true,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _inloggen(),
                        decoration: veld(l.dawarichWachtwoord),
                      ),
                    ],
                    if (_fout case final fout?) ...[
                      const SizedBox(height: 12),
                      Text(
                        fout,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _bezig ? null : _inloggen,
                        child: _bezig
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(l.dawarichInloggen),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Ingelogd extends ConsumerWidget {
  const _Ingelogd(this.account);

  final DawarichAccount account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final deel = ref.watch(deelInstellingenProvider);
    final notifier = ref.read(dawarichProvider.notifier);
    return InstellingenLijst(
      children: [
        InstellingenSectie(
          titel: l.dawarichAccount,
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(l.dawarichIngelogdAls(account.email)),
              subtitle: Text(account.server),
              trailing: TextButton(
                onPressed: notifier.uitloggen,
                child: Text(l.dawarichUitloggen),
              ),
            ),
          ],
        ),
        InstellingenSectie(
          titel: l.dawarichFamilie,
          children: [
            _FamilieDelen(account),
            SwitchListTile(
              secondary: const Icon(Icons.groups_outlined),
              title: Text(l.dawarichToonFamilie),
              subtitle: Text(l.dawarichToonFamilieUitleg),
              value: account.toonFamilie,
              onChanged: account.familie ? notifier.zetToonFamilie : null,
            ),
          ],
        ),
        InstellingenSectie(
          titel: l.dawarichNavigeren,
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.share_location),
              title: Text(l.dawarichDelenOnderweg),
              subtitle: Text(l.dawarichDelenOnderwegUitleg),
              value: deel.aan && deeltViaDawarich(deel, account),
              onChanged: notifier.zetDelenOnderweg,
            ),
          ],
        ),
      ],
    );
  }
}

/// De schakelaar om je locatie met de familie te delen, of waarom dat niet
/// kan.
class _FamilieDelen extends ConsumerWidget {
  const _FamilieDelen(this.account);

  final DawarichAccount account;

  Future<DeelDuur?> _kiesDuur(BuildContext context) =>
      showModalBottomSheet<DeelDuur>(
        context: context,
        builder: (context) {
          final l = AppLocalizations.of(context);
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    l.dawarichHoeLang,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final duur in DeelDuur.values)
                  ListTile(
                    title: Text(l.dawarichDuur(duur.name)),
                    onTap: () => Navigator.pop(context, duur),
                  ),
              ],
            ),
          );
        },
      );

  Future<void> _zet(BuildContext context, WidgetRef ref, bool aan) async {
    final l = AppLocalizations.of(context);
    final boodschapper = ScaffoldMessenger.of(context);
    DeelDuur? duur;
    if (aan) {
      duur = await _kiesDuur(context);
      if (duur == null) return;
    }
    try {
      await ref.read(familieProvider.notifier).zetDelen(aan, duur: duur);
    } on DawarichFout catch (fout) {
      boodschapper.showSnackBar(
        SnackBar(content: Text(dawarichFoutTekst(l, fout))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (!account.familie) {
      return ListTile(
        leading: const Icon(Icons.family_restroom),
        title: Text(l.dawarichGeenAbonnement),
      );
    }
    final familie = ref.watch(familieProvider);
    if (familie.value case final status?) {
      final tot = status.verlooptOm;
      return SwitchListTile(
        secondary: const Icon(Icons.family_restroom),
        title: Text(l.dawarichFamilieDelen),
        subtitle: Text(
          !status.delenAan
              ? l.dawarichDeeltNiet
              : tot == null
              ? l.dawarichDeeltAltijd
              : l.dawarichDeeltTot(_tijd(l, tot)),
        ),
        value: status.delenAan,
        onChanged: familie.isLoading ? null : (aan) => _zet(context, ref, aan),
      );
    }
    if (familie.error case final fout?) {
      final geenFamilie =
          fout is DawarichFout && fout.soort == DawarichFoutSoort.geenFamilie;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dawarichFoutTekst(l, fout)),
            Align(
              alignment: Alignment.centerLeft,
              child: geenFamilie
                  ? TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse('${account.server}/family'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text(l.dawarichNaarWebsite),
                    )
                  : TextButton(
                      onPressed: () => ref.invalidate(familieProvider),
                      child: Text(l.opnieuwProberen),
                    ),
            ),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: LinearProgressIndicator(),
    );
  }

  /// Vandaag alleen de tijd, anders ook de dag.
  static String _tijd(AppLocalizations l, DateTime tijd) {
    final nu = DateTime.now();
    final vandaag =
        tijd.year == nu.year && tijd.month == nu.month && tijd.day == nu.day;
    return vandaag
        ? DateFormat.Hm(l.localeName).format(tijd)
        : DateFormat.MMMd(l.localeName).add_Hm().format(tijd);
  }
}
