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
import 'dawarich_website.dart';
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
  // In de browser is een geweigerd CORS-verzoek niet van "offline" te
  // onderscheiden; dan is CORS het waarschijnlijkst.
  DawarichFout(soort: DawarichFoutSoort.verbinding, :final detail) =>
    kIsWeb ? l.dawarichFoutCors : l.dawarichFoutVerbinding(detail ?? ''),
  DawarichFout(soort: DawarichFoutSoort.geenDawarich) =>
    l.dawarichFoutGeenDawarich,
  DawarichFout(:final detail) => l.dawarichFoutOnbekend(detail ?? ''),
  _ => l.dawarichFoutOnbekend('$fout'),
};

/// Dawarich: eerst de verbinding (server, dan inloggen), pas daarna de
/// instellingen: familie delen, delen tijdens het navigeren en de familie op
/// de kaart.
class DawarichInstellingen extends ConsumerWidget {
  const DawarichInstellingen({super.key});

  /// Inloggen op de website; in tests te vervangen, want daar is geen
  /// WebView.
  @visibleForTesting
  static Future<String?> Function(BuildContext context, String server)
  openWebsite = DawarichWebsiteLogin.open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(dawarichProvider);
    return account == null ? const _Verbinden() : _Ingelogd(account);
  }
}

/// Een fout onder in een stap, opvallend maar rustig.
class _Melding extends StatelessWidget {
  const _Melding(this.tekst, {this.actie});

  final String tekst;
  final Widget? actie;

  @override
  Widget build(BuildContext context) {
    final kleuren = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Material(
        color: kleuren.errorContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: kleuren.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tekst,
                  style: TextStyle(color: kleuren.onErrorContainer),
                ),
              ),
              ?actie,
            ],
          ),
        ),
      ),
    );
  }
}

/// Een knop met een draaiend rondje zolang hij bezig is.
class _Knop extends StatelessWidget {
  const _Knop({required this.tekst, required this.bezig, this.onPressed});

  final String tekst;
  final bool bezig;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: FilledButton(
      onPressed: bezig ? null : onPressed,
      child: bezig
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(tekst),
    ),
  );
}

/// Niet ingelogd: stap 1 de server (is daar een Dawarich?), stap 2 inloggen.
class _Verbinden extends ConsumerStatefulWidget {
  const _Verbinden();

  @override
  ConsumerState<_Verbinden> createState() => _VerbindenState();
}

class _VerbindenState extends ConsumerState<_Verbinden> {
  late final _server = TextEditingController(
    text: ref.read(dawarichProvider.notifier).vorigeServer ?? '',
  );
  final _email = TextEditingController();
  final _wachtwoord = TextEditingController();
  final _sleutel = TextEditingController();

  /// Na stap 1: het adres waar Dawarich antwoordde, en zijn versie.
  String? _verbonden;
  String? _versie;
  bool _metSleutel = false;
  bool _bezig = false;
  String? _fout;

  @override
  void dispose() {
    for (final c in [_server, _email, _wachtwoord, _sleutel]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Iets dat de server vraagt, met het rondje en de fout eromheen.
  Future<void> _doe(Future<void> Function() werk) async {
    final l = AppLocalizations.of(context);
    setState(() {
      _bezig = true;
      _fout = null;
    });
    try {
      await werk();
    } on DawarichFout catch (fout) {
      if (mounted) setState(() => _fout = dawarichFoutTekst(l, fout));
    } finally {
      if (mounted) setState(() => _bezig = false);
    }
  }

  Future<void> _verbind() async {
    final l = AppLocalizations.of(context);
    final server = DawarichService.normaliseer(_server.text);
    if (server == null) {
      setState(() => _fout = l.serverOngeldig);
      return;
    }
    await _doe(() async {
      final info = await ref.read(dawarichServiceProvider).verbind(server);
      if (!mounted) return;
      setState(() {
        _verbonden = server;
        _versie = info.versie;
      });
    });
  }

  void _wijzigServer() => setState(() {
    _verbonden = null;
    _fout = null;
  });

  Future<void> _metWachtwoord() => _doe(() async {
    final server = _verbonden!;
    final notifier = ref.read(dawarichProvider.notifier);
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
  });

  Future<void> _viaWebsite() => _doe(() async {
    final server = _verbonden!;
    final sleutel = await DawarichInstellingen.openWebsite(context, server);
    // Null: teruggegaan zonder in te loggen.
    if (sleutel == null) return;
    if (sleutel.isEmpty) {
      throw const DawarichFout(DawarichFoutSoort.onbekend, 'geen sleutel');
    }
    await ref.read(dawarichProvider.notifier).metSleutel(server, sleutel);
  });

  Future<void> _metApiSleutel() => _doe(
    () => ref
        .read(dawarichProvider.notifier)
        .metSleutel(_verbonden!, _sleutel.text),
  );

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

  static InputDecoration _veld(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    border: const OutlineInputBorder(),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fout = _fout == null ? null : _Melding(_fout!);
    final verbonden = _verbonden;

    // Stap 1: waar staat je Dawarich?
    if (verbonden == null) {
      return InstellingenLijst(
        children: [
          InstellingenSectie(
            titel: l.dawarichStapServer,
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
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _verbind(),
                      decoration: _veld(
                        l.dawarichServer,
                        hint: 'https://dawarich.example',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Knop(
                      tekst: l.dawarichVerbinden,
                      bezig: _bezig,
                      onPressed: _verbind,
                    ),
                  ],
                ),
              ),
            ],
          ),
          ?fout,
        ],
      );
    }

    // Stap 2: inloggen.
    return AutofillGroup(
      child: InstellingenLijst(
        children: [
          InstellingenSectie(
            titel: l.dawarichStapServer,
            children: [
              ListTile(
                leading: Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(Uri.parse(verbonden).host),
                subtitle: Text(
                  _versie == null
                      ? l.dawarichVerbonden
                      : l.dawarichVerbondenVersie(_versie!),
                ),
                trailing: TextButton(
                  onPressed: _bezig ? null : _wijzigServer,
                  child: Text(l.dawarichWijzigen),
                ),
              ),
            ],
          ),
          ?fout,
          InstellingenSectie(
            titel: l.dawarichStapInloggen,
            children: [
              SectieBlok(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: _veld(l.dawarichEmail),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _wachtwoord,
                      obscureText: true,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _metWachtwoord(),
                      decoration: _veld(l.dawarichWachtwoord),
                    ),
                    const SizedBox(height: 16),
                    _Knop(
                      tekst: l.dawarichInloggen,
                      bezig: _bezig && !_metSleutel,
                      onPressed: _metWachtwoord,
                    ),
                  ],
                ),
              ),
            ],
          ),
          InstellingenSectie(
            titel: l.dawarichAndereManieren,
            children: [
              if (!kIsWeb)
                ListTile(
                  leading: const Icon(Icons.open_in_browser),
                  title: Text(l.dawarichWebsiteInloggen),
                  subtitle: Text(l.dawarichWebsiteUitleg),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !_bezig,
                  onTap: _viaWebsite,
                ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(l.dawarichMetSleutel),
                subtitle: Text(l.dawarichSleutelUitleg),
                trailing: Icon(
                  _metSleutel ? Icons.expand_less : Icons.expand_more,
                ),
                onTap: () => setState(() => _metSleutel = !_metSleutel),
              ),
              if (_metSleutel)
                SectieBlok(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _sleutel,
                        obscureText: true,
                        autocorrect: false,
                        onSubmitted: (_) => _metApiSleutel(),
                        decoration: _veld(l.dawarichSleutel),
                      ),
                      const SizedBox(height: 16),
                      _Knop(
                        tekst: l.dawarichInloggen,
                        bezig: _bezig,
                        onPressed: _metApiSleutel,
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

/// Ingelogd: eerst of de verbinding nog werkt; de instellingen pas als dat
/// zo is.
class _Ingelogd extends ConsumerWidget {
  const _Ingelogd(this.account);

  final DawarichAccount account;

  Future<void> _uitloggen(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final zeker = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.dawarichUitloggenVraag),
        content: Text(l.dawarichUitloggenUitleg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.annuleren),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.dawarichUitloggen),
          ),
        ],
      ),
    );
    if (zeker ?? false) await ref.read(dawarichProvider.notifier).uitloggen();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final kleuren = Theme.of(context).colorScheme;
    final deel = ref.watch(deelInstellingenProvider);
    final notifier = ref.read(dawarichProvider.notifier);
    final verbinding = ref.watch(dawarichVerbindingProvider);
    final fout = verbinding.error;
    final verlopen =
        fout is DawarichFout && fout.soort == DawarichFoutSoort.inlog;
    final host = Uri.parse(account.server).host;
    final (status, statusKleur) = switch (verbinding) {
      _ when verlopen => (l.dawarichSessieVerlopen, kleuren.error),
      AsyncValue(hasError: true) => (l.dawarichNietBereikbaar, kleuren.error),
      AsyncValue(isLoading: true) => (l.dawarichControleren, null),
      AsyncValue(:final value) => (
        value?.versie == null
            ? l.dawarichVerbonden
            : l.dawarichVerbondenVersie(value!.versie!),
        null,
      ),
    };

    return InstellingenLijst(
      children: [
        InstellingenSectie(
          titel: l.dawarichAccount,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: kleuren.primaryContainer,
                foregroundColor: kleuren.onPrimaryContainer,
                child: Text(
                  account.email.isEmpty
                      ? '?'
                      : account.email.substring(0, 1).toUpperCase(),
                ),
              ),
              title: Text(account.email.isEmpty ? host : account.email),
              subtitle: Text(
                '$host · $status',
                style: TextStyle(color: statusKleur),
              ),
              trailing: TextButton(
                onPressed: () => _uitloggen(context, ref),
                child: Text(l.dawarichUitloggen),
              ),
            ),
          ],
        ),
        // De sleutel werkt niet meer: alleen opnieuw inloggen, met de server
        // al ingevuld.
        if (verlopen)
          _Melding(
            l.dawarichSessieVerlopenUitleg,
            actie: TextButton(
              onPressed: notifier.uitloggen,
              child: Text(l.dawarichOpnieuwInloggen),
            ),
          )
        else ...[
          if (fout != null)
            _Melding(
              dawarichFoutTekst(l, fout),
              actie: TextButton(
                onPressed: () => ref.invalidate(dawarichVerbindingProvider),
                child: Text(l.opnieuwProberen),
              ),
            ),
          if (verbinding.isLoading && !verbinding.hasValue)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            )
          else ...[
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
        ],
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
