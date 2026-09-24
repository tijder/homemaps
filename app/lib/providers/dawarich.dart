import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dawarich.dart';
import '../models/locatie_delen.dart';
import '../services/dawarich_service.dart';
import 'diensten.dart';
import 'instellingen.dart';
import 'locatie_delen.dart';

/// De API-sleutel van Dawarich; niet in de gewone opslag.
final dawarichGeheimProvider = Provider<GeheimOpslag>(
  (ref) => const VeiligeGeheimOpslag('dawarichSleutel'),
);

final dawarichServiceProvider = Provider<DawarichService>(
  (ref) => DawarichService(ref.watch(dioProvider)),
);

/// Het adres waar het delen tijdens het navigeren heen gaat.
String dawarichPuntenUrl(String server) => '$server/api/v1/owntracks/points';

/// Wijzen de algemene deel-instellingen naar dit Dawarich-account?
bool deeltViaDawarich(DeelInstellingen deel, DawarichAccount? account) =>
    account != null &&
    deel.sjabloon == DeelSjabloon.dawarich &&
    deel.url == dawarichPuntenUrl(account.server);

/// Het ingelogde Dawarich-account, of null.
class DawarichNotifier extends Notifier<DawarichAccount?> {
  static const _sleutel = 'dawarich';

  String? _api;

  /// Klaar als de sleutel uit de veilige opslag gelezen is.
  late Future<void> geladen;

  /// De API-sleutel, zodra [geladen] klaar is.
  String? get sleutel => _api;

  @override
  DawarichAccount? build() {
    final account = DawarichAccount.vanMap(
      ref.watch(instellingenDoosProvider)?.get(_sleutel),
    );
    geladen = account == null ? Future.value() : _laadSleutel();
    return account;
  }

  Future<void> _laadSleutel() async {
    try {
      _api = await ref.read(dawarichGeheimProvider).lees();
    } on Object catch (fout) {
      debugPrint('Dawarich-sleutel niet te lezen: $fout');
    }
  }

  Future<void> _bewaar(DawarichAccount? account) async {
    state = account;
    final doos = ref.read(instellingenDoosProvider);
    await (account == null
        ? doos?.delete(_sleutel)
        : doos?.put(_sleutel, account.naarMap()));
  }

  /// Na het inloggen: sleutel opslaan, en vragen of familie kan.
  Future<void> _ingelogd(String sleutel, DawarichAccount account) async {
    var volledig = account;
    try {
      final me = await ref
          .read(dawarichServiceProvider)
          .controleerSleutel(account.server, sleutel);
      volledig = account.kopie(familie: me.familie);
    } on DawarichFout {
      // Dan maar aannemen dat het kan; familie() zegt het anders wel.
    }
    _api = sleutel;
    await ref.read(dawarichGeheimProvider).schrijf(sleutel);
    await _bewaar(volledig);
  }

  /// Met e-mail en wachtwoord. Geeft [DawarichTweeStap] als er nog een code
  /// nodig is; daarna [bevestig].
  Future<DawarichLogin> inloggen(
    String server,
    String email,
    String wachtwoord,
  ) async {
    final uitslag = await ref
        .read(dawarichServiceProvider)
        .login(server, email.trim(), wachtwoord);
    if (uitslag case DawarichIngelogd(:final sleutel, :final account)) {
      await _ingelogd(sleutel, account);
    }
    return uitslag;
  }

  /// De code van de tweestapsverificatie.
  Future<void> bevestig(String server, String token, String code) async {
    final uitslag = await ref
        .read(dawarichServiceProvider)
        .otp(server, token, code);
    await _ingelogd(uitslag.sleutel, uitslag.account);
  }

  /// Met een API-sleutel uit Dawarich (Instellingen, API-sleutel).
  Future<void> metSleutel(String server, String sleutel) async {
    final schoon = sleutel.trim();
    final account = await ref
        .read(dawarichServiceProvider)
        .controleerSleutel(server, schoon);
    _api = schoon;
    await ref.read(dawarichGeheimProvider).schrijf(schoon);
    await _bewaar(account);
  }

  /// Uitloggen; delen tijdens het navigeren naar dit account stopt ook.
  Future<void> uitloggen() async {
    final deel = ref.read(deelInstellingenProvider);
    if (deeltViaDawarich(deel, state)) {
      await ref.read(deelInstellingenProvider.notifier).geladen;
      await ref
          .read(deelInstellingenProvider.notifier)
          .wijzig(
            ref.read(deelInstellingenProvider).kopie(aan: false, geheim: ''),
          );
    }
    _api = null;
    await ref.read(dawarichGeheimProvider).schrijf('');
    await _bewaar(null);
  }

  Future<void> zetToonFamilie(bool aan) async {
    final account = state;
    if (account != null) await _bewaar(account.kopie(toonFamilie: aan));
  }

  /// Delen tijdens het navigeren: vult de algemene deel-instellingen met dit
  /// account, of zet ze uit.
  Future<void> zetDelenOnderweg(bool aan) async {
    final account = state;
    await geladen;
    final sleutel = _api;
    final notifier = ref.read(deelInstellingenProvider.notifier);
    await notifier.geladen;
    final deel = ref.read(deelInstellingenProvider);
    if (!aan) {
      if (deel.aan) await notifier.wijzig(deel.kopie(aan: false));
      return;
    }
    if (account == null || sleutel == null) return;
    await notifier.wijzig(
      deel
          .metSjabloon(DeelSjabloon.dawarich)
          .kopie(
            aan: true,
            url: dawarichPuntenUrl(account.server),
            inlog: DeelInlog.bearer,
            geheim: sleutel,
          ),
    );
  }
}

final dawarichProvider = NotifierProvider<DawarichNotifier, DawarichAccount?>(
  DawarichNotifier.new,
);

/// Jouw plek in de familie; null als je niet bent ingelogd. Een
/// [DawarichFout] met [DawarichFoutSoort.geenFamilie] als je in geen familie
/// zit.
class FamilieNotifier extends AsyncNotifier<FamilieStatus?> {
  @override
  Future<FamilieStatus?> build() async {
    final account = ref.watch(dawarichProvider);
    if (account == null) return null;
    final notifier = ref.read(dawarichProvider.notifier);
    await notifier.geladen;
    final sleutel = notifier.sleutel;
    if (sleutel == null) return null;
    return ref.read(dawarichServiceProvider).familie(account.server, sleutel);
  }

  /// Je locatie met de familie delen: aan (voor [duur]) of uit.
  Future<void> zetDelen(bool aan, {DeelDuur? duur}) async {
    final account = ref.read(dawarichProvider);
    final sleutel = ref.read(dawarichProvider.notifier).sleutel;
    if (account == null || sleutel == null) return;
    await ref
        .read(dawarichServiceProvider)
        .zetDelen(account.server, sleutel, aan: aan, duur: duur);
    ref.invalidateSelf();
    await future;
  }
}

final familieProvider = AsyncNotifierProvider<FamilieNotifier, FamilieStatus?>(
  FamilieNotifier.new,
);

/// Hoe vaak de plekken van de familie worden opgehaald. Dawarich heeft voor
/// een API-sleutel geen live kanaal.
const familieInterval = Duration(seconds: 30);

/// De familieleden die hun locatie delen, voor op de kaart; leeg als dat uit
/// staat. Alleen opgehaald als de app op de voorgrond is. Mislukt het, dan
/// blijven de vorige plekken staan (ze worden vanzelf grijs).
class FamilieLocatiesNotifier extends Notifier<List<FamilieLocatie>> {
  @override
  List<FamilieLocatie> build() {
    final account = ref.watch(dawarichProvider);
    if (account == null || !account.toonFamilie) return const [];
    final tik = Timer.periodic(familieInterval, (_) => haal());
    final levensloop = AppLifecycleListener(onResume: haal);
    ref.onDispose(() {
      tik.cancel();
      levensloop.dispose();
    });
    Future.microtask(haal);
    return const [];
  }

  Future<void> haal() async {
    final staat = WidgetsBinding.instance.lifecycleState;
    if (staat != null && staat != AppLifecycleState.resumed) return;
    final account = ref.read(dawarichProvider);
    if (account == null || !account.toonFamilie) return;
    final notifier = ref.read(dawarichProvider.notifier);
    await notifier.geladen;
    final sleutel = notifier.sleutel;
    if (sleutel == null) return;
    try {
      final alle = await ref
          .read(dawarichServiceProvider)
          .locaties(account.server, sleutel);
      // Tussendoor uitgelogd of uitgezet: niets meer tonen.
      if (!ref.mounted) return;
      state = [
        for (final lid in alle)
          if (lid.userId != account.userId && lid.email != account.email) lid,
      ];
    } on DawarichFout catch (fout) {
      debugPrint('Familie niet op te halen: $fout');
    }
  }
}

final familieLocatiesProvider =
    NotifierProvider<FamilieLocatiesNotifier, List<FamilieLocatie>>(
      FamilieLocatiesNotifier.new,
    );
