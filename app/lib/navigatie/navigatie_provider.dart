import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/app_localizations.dart';
import '../models/plaats.dart';
import '../models/profiel.dart';
import '../models/route.dart';
import '../providers/diensten.dart';
import '../providers/instellingen.dart';
import '../providers/locatie.dart';
import '../services/valhalla_service.dart';
import 'aankondiger.dart';
import 'simulatie.dart';
import 'stem.dart';
import 'volger.dart';

/// Wat de navigatie in de taal van de gebruiker zegt en laat zien. Het scherm
/// maakt dit uit de vertalingen; de notifier heeft zelf geen context.
class NavTeksten {
  const NavTeksten({
    required this.taal,
    required this.meldingTitel,
    required this.meldingTekst,
    required this.herberekenen,
    required this.snellereRoute,
    required this.metAfstand,
  });

  /// Voor de stem, bijvoorbeeld 'nl-NL'.
  final String taal;

  /// De blijvende melding op Android zolang de navigatie loopt.
  final String meldingTitel;
  final String meldingTekst;
  final String herberekenen;
  final String Function(int minutenSneller) snellereRoute;
  final String Function(double meters, String zin) metAfstand;

  /// [taal] zoals Valhalla hem kent ('nl-NL', 'en-US').
  factory NavTeksten.uit(AppLocalizations l, String taal, String bestemming) {
    final getal = NumberFormat('#0.#', taal.replaceAll('-', '_'));
    String gesproken(double meters) => meters < 1000
        // Op 50 m: "over 437 meter" klinkt als een meetfout.
        ? l.gesprokenMeter(max(50, (meters / 50).round() * 50))
        : l.gesprokenKilometer(getal.format(meters / 1000));
    return NavTeksten(
      taal: taal,
      meldingTitel: l.navigatieMeldingTitel(bestemming),
      meldingTekst: l.navigatieMeldingTekst,
      herberekenen: l.herberekenen,
      snellereRoute: l.snellereRoute,
      metAfstand: (meters, zin) => l.overAfstand(
        gesproken(meters),
        // "Over 400 meter links afslaan", niet "... Links afslaan".
        zin.isEmpty ? zin : zin[0].toLowerCase() + zin.substring(1),
      ),
    );
  }
}

class NavigatieToestand {
  const NavigatieToestand({
    required this.route,
    required this.doelen,
    this.stand,
    this.fix,
    this.gedempt = false,
    this.herberekent = false,
    this.aangekomen = false,
  });

  final RouteOptie route;

  /// Wat er nog komt: de via-punten en de bestemming.
  final List<Plaats> doelen;
  final NavStand? stand;
  final LocatieFix? fix;
  final bool gedempt;
  final bool herberekent;
  final bool aangekomen;

  NavigatieToestand kopie({
    RouteOptie? route,
    List<Plaats>? doelen,
    NavStand? stand,
    LocatieFix? fix,
    bool? gedempt,
    bool? herberekent,
    bool? aangekomen,
  }) => NavigatieToestand(
    route: route ?? this.route,
    doelen: doelen ?? this.doelen,
    stand: stand ?? this.stand,
    fix: fix ?? this.fix,
    gedempt: gedempt ?? this.gedempt,
    herberekent: herberekent ?? this.herberekent,
    aangekomen: aangekomen ?? this.aangekomen,
  );
}

/// Null zolang er niet genavigeerd wordt.
class NavigatieNotifier extends Notifier<NavigatieToestand?> {
  RouteVolger? _volger;
  Aankondiger? _aankondiger;
  ProviderSubscription<LocatieFix?>? _fixes;
  Timer? _verkeer;
  CancelToken? _lopend;
  DateTime _laatsteHerberekening = DateTime(0);

  /// Via-punten op de huidige route die al voorbij zijn (en uit de doelen weg).
  int _viaVoorbij = 0;
  late NavTeksten _teksten;
  late Profiel _profiel;

  /// Een herberekening onderweg hooguit zo vaak: op een plek zonder route (een
  /// parkeerterrein) zou het anders elke seconde gebeuren.
  static const _rustTussenHerberekeningen = Duration(seconds: 10);

  /// Verder dan dit van de route bij de start: meteen herberekenen.
  static const _verVanBegin = 150.0;

  /// Voor de auto: zo vaak kijken of er door het verkeer een snellere route is
  /// (de importer ververst het verkeer net zo vaak).
  static const verkeerInterval = Duration(minutes: 5);

  /// Vastgelegd bij de start: bij het opruimen mag ref niet meer.
  Stem? _stemBijStart;
  bool _actief = false;

  @override
  NavigatieToestand? build() {
    ref.onDispose(() => _ruimOp(provider: false));
    return null;
  }

  Stem get _stem => _stemBijStart ?? ref.read(stemProvider);

  Future<void> start({
    required RouteOptie route,
    required List<Plaats> doelen,
    required NavTeksten teksten,
  }) async {
    _ruimOp();
    _actief = true;
    _stemBijStart = ref.read(stemProvider);
    _teksten = teksten;
    _profiel = ref.read(instellingenProvider).profiel;
    _nieuweRoute(route, doelen);
    await WakelockPlus.enable().catchError((Object _) {});
    await _stem.begin(teksten.taal).catchError((Object _) {});
    ref.read(locatieProvider.notifier).navigatie((
      titel: teksten.meldingTitel,
      tekst: teksten.meldingTekst,
    ));
    _fixes = ref.listen(locatieProvider.select((t) => t.fix), (_, fix) {
      if (fix != null) _bijFix(fix);
    }, fireImmediately: true);
    if (_profiel == Profiel.auto &&
        ref.read(instellingenProvider).liveVerkeer) {
      _verkeer = Timer.periodic(verkeerInterval, (_) => _zoekSneller());
    }
  }

  void stop() {
    _ruimOp();
    state = null;
  }

  void dempen(bool gedempt) {
    if (gedempt) _stem.stop();
    state = state?.kopie(gedempt: gedempt);
  }

  /// [provider]: ook de locatiestroom terug naar gewoon. Niet bij het
  /// opruimen van de provider zelf; dan is ref niet meer te gebruiken.
  void _ruimOp({bool provider = true}) {
    _fixes?.close();
    _fixes = null;
    _verkeer?.cancel();
    _verkeer = null;
    _lopend?.cancel();
    if (!_actief) return;
    _actief = false;
    WakelockPlus.disable().catchError((Object _) {});
    _stemBijStart?.stop().catchError((Object _) {});
    if (provider) ref.read(locatieProvider.notifier).navigatie(null);
  }

  void _nieuweRoute(RouteOptie route, List<Plaats> doelen) {
    _viaVoorbij = 0;
    _volger = RouteVolger(route);
    _aankondiger = Aankondiger(
      route,
      _profiel,
      metAfstand: _teksten.metAfstand,
    );
    final bron = ref.read(locatieBronProvider);
    if (bron is SimulatieBron) bron.rijd(route);
    state = NavigatieToestand(
      route: route,
      doelen: doelen,
      fix: state?.fix,
      gedempt: state?.gedempt ?? false,
    );
  }

  void _bijFix(LocatieFix fix) {
    final nu = state, volger = _volger, aankondiger = _aankondiger;
    if (nu == null || volger == null || aankondiger == null || nu.aangekomen) {
      return;
    }
    final stand = volger.werkBij(fix);
    // De eerste fix ligt ver van het begin ("van" was een ander adres): niet
    // eerst die route voorlezen, meteen een nieuwe vanaf hier.
    if (nu.stand == null &&
        stand.afwijking > _verVanBegin &&
        DateTime.now().difference(_laatsteHerberekening) >
            _rustTussenHerberekeningen) {
      state = nu.kopie(stand: stand, fix: fix);
      _herbereken(fix, stil: false);
      return;
    }
    if (!nu.gedempt) {
      for (final zin in aankondiger.bij(stand, fix.snelheid ?? 0)) {
        _stem.zeg(zin);
      }
    }
    // Voorbij een via-punt: dat hoort niet meer bij de volgende herberekening.
    // De bestemming zelf blijft altijd staan.
    final voorbij = [
      for (var i = 0; i < stand.volgende; i++)
        if (nu.route.manoeuvres[i].isBestemming) i,
    ].length;
    var doelen = nu.doelen;
    if (voorbij > _viaVoorbij && doelen.length > 1) {
      final weg = (voorbij - _viaVoorbij).clamp(0, doelen.length - 1);
      doelen = doelen.sublist(weg);
      _viaVoorbij = voorbij;
    }
    state = nu.kopie(
      stand: stand,
      fix: fix,
      aangekomen: stand.aangekomen,
      doelen: doelen,
    );
    if (stand.aangekomen) {
      // Klaar: geen scherm-aan en geen achtergronddienst meer. Het scherm laat
      // "aangekomen" staan tot je hem wegtikt.
      _fixes?.close();
      _fixes = null;
      _verkeer?.cancel();
      WakelockPlus.disable().catchError((Object _) {});
      ref.read(locatieProvider.notifier).navigatie(null);
      return;
    }
    if (stand.vanRoute &&
        !nu.herberekent &&
        DateTime.now().difference(_laatsteHerberekening) >
            _rustTussenHerberekeningen) {
      if (!nu.gedempt) _stem.zeg(_teksten.herberekenen);
      _herbereken(fix, stil: false);
    }
  }

  /// Elke paar minuten, voor de auto: is er vanaf hier nu een duidelijk snellere
  /// weg? Dan zonder vragen over, met een zin erover.
  void _zoekSneller() {
    final nu = state;
    if (nu == null || nu.herberekent || nu.aangekomen) return;
    final fix = nu.fix;
    if (fix != null) _herbereken(fix, stil: true);
  }

  Future<void> _herbereken(LocatieFix fix, {required bool stil}) async {
    final nu = state;
    final valhalla = ref.read(valhallaProvider);
    if (nu == null || valhalla == null) return;
    _laatsteHerberekening = DateTime.now();
    final annuleer = _lopend = CancelToken();
    state = nu.kopie(herberekent: true);
    final instellingen = ref.read(instellingenProvider);
    try {
      final routes = await valhalla.route(
        [fix.punt, for (final doel in nu.doelen) doel.punt],
        _profiel,
        taal: _teksten.taal,
        liveVerkeer: instellingen.liveVerkeer,
        vermijdSnelwegen: instellingen.vermijdSnelwegen,
        vermijdTol: instellingen.vermijdTol,
        vermijdVeren: instellingen.vermijdVeren,
        alternatieven: false,
        koers: fix.koers,
        annuleer: annuleer,
      );
      final huidig = state;
      if (annuleer.isCancelled || huidig == null || routes.isEmpty) return;
      final nieuw = routes.first;
      if (stil) {
        final rest = huidig.stand?.restSeconden ?? huidig.route.seconden;
        final winst = rest - nieuw.seconden;
        // Alleen bij echte winst: twee minuten, en minstens een tiende.
        if (winst < 120 || winst < rest * 0.1) {
          state = huidig.kopie(herberekent: false);
          return;
        }
        if (!huidig.gedempt) {
          _stem.zeg(_teksten.snellereRoute((winst / 60).round()));
        }
      }
      _nieuweRoute(nieuw, huidig.doelen);
      // Meteen de laatste fix erop, anders staat er tot de volgende niets.
      if (state?.fix case final laatste?) _bijFix(laatste);
    } on DioException {
      // Geen netwerk: de oude route blijft, over tien seconden opnieuw.
      state = state?.kopie(herberekent: false);
    } on RouteFout {
      state = state?.kopie(herberekent: false);
    }
  }
}

final navigatieProvider =
    NotifierProvider<NavigatieNotifier, NavigatieToestand?>(
      NavigatieNotifier.new,
    );
