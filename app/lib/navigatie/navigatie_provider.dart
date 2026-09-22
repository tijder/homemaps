import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
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
    required this.waarschuwing,
  });

  /// Voor de stem, bijvoorbeeld 'nl-NL'.
  final String taal;

  /// De blijvende melding op Android zolang de navigatie loopt.
  final String meldingTitel;
  final String meldingTekst;
  final String herberekenen;
  final String Function(int minutenSneller) snellereRoute;
  final String Function(double meters, String zin) metAfstand;

  /// "Let op: ongeval over 2 kilometer." voor een melding op de route.
  final String Function(String soort, double meters) waarschuwing;

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
      waarschuwing: (soort, meters) => l.waarschuwingOpRoute(
        switch (soort) {
          'ongeval' => l.meldingOngeval,
          'pech' => l.meldingPech,
          _ => l.meldingObstakel,
        }.toLowerCase(),
        gesproken(meters),
      ),
      metAfstand: (meters, zin) => l.overAfstand(
        gesproken(meters),
        // "Over 400 meter links afslaan", niet "... Links afslaan".
        zin.isEmpty ? zin : zin[0].toLowerCase() + zin.substring(1),
      ),
    );
  }
}

/// Een snellere route die het verkeer onderweg opleverde; de gebruiker kiest.
class Voorstel {
  const Voorstel(this.route, this.secondenSneller, this.verloopt);

  final RouteOptie route;
  final double secondenSneller;

  /// Zonder keuze vervalt hij dan, en blijft de huidige route.
  final DateTime verloopt;

  /// De weg waar het verschil in zit: de langste manoeuvre met een naam, voor
  /// "via N303".
  String? get via {
    Manoeuvre? langste;
    for (final m in route.manoeuvres) {
      if (m.straten.isNotEmpty &&
          (langste == null || m.meters > langste.meters)) {
        langste = m;
      }
    }
    return langste?.straten.first;
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
    this.voorstel,
    this.limiet,
  });

  final RouteOptie route;

  /// Wat er nog komt: de via-punten en de bestemming.
  final List<Plaats> doelen;
  final NavStand? stand;
  final LocatieFix? fix;
  final bool gedempt;
  final bool herberekent;
  final bool aangekomen;
  final Voorstel? voorstel;

  /// De maximumsnelheid hier (km/u), of null als onbekend.
  final int? limiet;

  NavigatieToestand kopie({
    RouteOptie? route,
    List<Plaats>? doelen,
    NavStand? stand,
    LocatieFix? fix,
    bool? gedempt,
    bool? herberekent,
    bool? aangekomen,
    Voorstel? Function()? voorstel,
    int? Function()? limiet,
  }) => NavigatieToestand(
    route: route ?? this.route,
    doelen: doelen ?? this.doelen,
    stand: stand ?? this.stand,
    fix: fix ?? this.fix,
    gedempt: gedempt ?? this.gedempt,
    herberekent: herberekent ?? this.herberekent,
    aangekomen: aangekomen ?? this.aangekomen,
    voorstel: voorstel != null ? voorstel() : this.voorstel,
    limiet: limiet != null ? limiet() : this.limiet,
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

  Timer? _voorstelVerloopt;

  /// Meldingen (ongeval, pech, voorwerp) op de huidige route, op volgorde van
  /// waar ze liggen; en welke al gezegd zijn.
  List<({String id, double langs, String soort})> _meldingen = const [];
  final _gewaarschuwd = <String>{};
  ProviderSubscription<Map<String, dynamic>?>? _verkeer2;

  /// Maximumsnelheid per stuk van de huidige route (zie
  /// [ValhallaService.snelheidsLimieten]); leeg tot ze binnen zijn.
  List<int?> _limieten = const [];

  /// Afgewezen routes (op hun lengte), om niet steeds dezelfde voor te stellen.
  final _afgewezen = <int>{};

  /// Zolang staat een voorstel er zonder keuze.
  static const voorstelDuur = Duration(seconds: 45);

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
    _afgewezen.clear();
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
    // Nieuwe verkeersgegevens (elke vijf minuten): opnieuw kijken wat er op de
    // route ligt.
    _verkeer2 = ref.listen(verkeerProvider.select((v) => v.value), (_, laag) {
      if (state case final nu?) _leesMeldingen(nu.route, laag);
    });
    _fixes = ref.listen(locatieProvider.select((t) => t.fix), (_, fix) {
      if (fix != null) _bijFix(fix);
    }, fireImmediately: true);
    if (_profiel == Profiel.auto &&
        ref.read(instellingenProvider).liveVerkeer) {
      _verkeer = Timer.periodic(verkeerInterval, (_) => zoekSneller());
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
    _verkeer2?.close();
    _verkeer2 = null;
    _verkeer?.cancel();
    _verkeer = null;
    _voorstelVerloopt?.cancel();
    _voorstelVerloopt = null;
    _lopend?.cancel();
    if (!_actief) return;
    _actief = false;
    WakelockPlus.disable().catchError((Object _) {});
    _stemBijStart?.stop().catchError((Object _) {});
    if (provider) ref.read(locatieProvider.notifier).navigatie(null);
  }

  void _nieuweRoute(RouteOptie route, List<Plaats> doelen) {
    _viaVoorbij = 0;
    _limieten = const [];
    _haalLimieten(route);
    _meldingen = const [];
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
    _leesMeldingen(route, ref.read(verkeerProvider).value);
  }

  /// Welke meldingen uit de verkeerslaag op deze route liggen: binnen 30 m
  /// van de lijn, en aan jouw kant van de weg (een ongeval op de andere
  /// rijbaan van de snelweg ligt er ook vlakbij).
  void _leesMeldingen(RouteOptie route, Map<String, dynamic>? laag) {
    final volger = _volger;
    if (laag == null || volger == null || !identical(volger.route, route)) {
      return;
    }
    final gevonden = <({String id, double langs, String soort})>[];
    for (final feature in (laag['features'] as List? ?? const [])) {
      if (feature is! Map) continue;
      final eigen = (feature['properties'] as Map?) ?? const {};
      final soort = eigen['soort'];
      final geometrie = feature['geometry'] as Map?;
      if (soort is! String ||
          !const {'ongeval', 'pech', 'obstakel'}.contains(soort) ||
          geometrie?['type'] != 'Point') {
        continue;
      }
      final c = (geometrie!['coordinates'] as List).cast<num>();
      final plek = volger.plaatsOp(LatLng(c[1].toDouble(), c[0].toDouble()));
      final koers = eigen['koers'];
      if (plek.afstand > 30) continue;
      if (koers is num && hoekVerschil(koers.toDouble(), plek.koers) > 90) {
        continue;
      }
      gevonden.add((
        id: '${feature['id']}:$soort:${c[0]},${c[1]}',
        langs: plek.langs,
        soort: soort,
      ));
    }
    gevonden.sort((a, b) => a.langs.compareTo(b.langs));
    _meldingen = gevonden;
  }

  /// Hoe ver vooruit een melding op de route gezegd wordt.
  double get _waarschuwAfstand => switch (_profiel) {
    Profiel.auto => 2000,
    Profiel.fiets => 500,
    Profiel.lopen => 200,
  };

  /// Op de achtergrond: de maximumsnelheden langs de route (alleen de auto).
  Future<void> _haalLimieten(RouteOptie route) async {
    final valhalla = ref.read(valhallaProvider);
    if (valhalla == null || _profiel != Profiel.auto) return;
    final limieten = await valhalla
        .snelheidsLimieten(route.punten, _profiel)
        .catchError((Object _) => null);
    // Intussen een andere route: deze hoort er niet meer bij.
    if (limieten != null && identical(state?.route, route)) {
      _limieten = limieten;
    }
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
      _herbereken(fix);
      return;
    }
    if (!nu.gedempt) {
      for (final zin in aankondiger.bij(stand, fix.snelheid ?? 0)) {
        _stem.zeg(zin);
      }
      // Een ongeval of pechgeval dat vóór je op de route ligt: één keer.
      for (final melding in _meldingen) {
        final vooruit = melding.langs - stand.langs;
        if (vooruit < 0) continue;
        if (vooruit > _waarschuwAfstand) break;
        if (_gewaarschuwd.add(melding.id)) {
          _stem.zeg(_teksten.waarschuwing(melding.soort, vooruit));
        }
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
      limiet: () =>
          stand.segment < _limieten.length ? _limieten[stand.segment] : null,
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
      _herbereken(fix);
    }
  }

  /// Elke paar minuten, voor de auto: is er vanaf hier nu een duidelijk snellere
  /// weg? Dan een voorstel; wisselen doet pas de gebruiker ([neemVoorstel]).
  ///
  /// Beide tijden komen op dezelfde manier tot stand -- de rest van de huidige
  /// route en de nieuwe, allebei over hun lijn met het verkeer van nu -- zodat
  /// een verschil echt aan het verkeer ligt en niet aan de rekenwijze.
  @visibleForTesting
  Future<void> zoekSneller() async {
    final nu = state;
    final valhalla = ref.read(valhallaProvider);
    final volger = _volger;
    final stand = nu?.stand, fix = nu?.fix;
    if (nu == null ||
        valhalla == null ||
        volger == null ||
        stand == null ||
        fix == null ||
        nu.herberekent ||
        nu.aangekomen ||
        nu.voorstel != null) {
      return;
    }
    final annuleer = _lopend = CancelToken();
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
      if (routes.isEmpty || annuleer.isCancelled) return;
      final nieuw = routes.first;
      if (_afgewezen.contains(_sleutel(nieuw))) return;
      final (huidigeTijd, nieuweTijd) = await (
        valhalla.reistijd(
          volger.rest(stand),
          _profiel,
          live: true,
          annuleer: annuleer,
        ),
        valhalla.reistijd(
          nieuw.punten,
          _profiel,
          live: true,
          annuleer: annuleer,
        ),
      ).wait;
      final huidig = state;
      if (huidigeTijd == null ||
          nieuweTijd == null ||
          huidig == null ||
          huidig.aangekomen ||
          annuleer.isCancelled) {
        return;
      }
      final winst = huidigeTijd - nieuweTijd;
      // Alleen bij echte winst: twee minuten, en minstens een tiende.
      if (winst < 120 || winst < huidigeTijd * 0.1) return;
      state = huidig.kopie(
        voorstel: () =>
            Voorstel(nieuw, winst, DateTime.now().add(voorstelDuur)),
      );
      if (!huidig.gedempt) {
        _stem.zeg(_teksten.snellereRoute((winst / 60).round()));
      }
      _voorstelVerloopt?.cancel();
      _voorstelVerloopt = Timer(voorstelDuur, negeerVoorstel);
    } on DioException {
      // Geen netwerk: de volgende keer opnieuw.
    } on RouteFout {
      // Geen route vanaf hier: de huidige blijft.
    }
  }

  /// "Nemen": vanaf nu de voorgestelde route.
  void neemVoorstel() {
    final nu = state, voorstel = nu?.voorstel;
    if (nu == null || voorstel == null) return;
    _voorstelVerloopt?.cancel();
    _nieuweRoute(voorstel.route, nu.doelen);
    if (state?.fix case final laatste?) _bijFix(laatste);
  }

  /// "Negeren", of 45 seconden niets gekozen: de huidige route blijft, en deze
  /// komt niet nog eens voorbij.
  void negeerVoorstel() {
    final nu = state, voorstel = nu?.voorstel;
    if (nu == null || voorstel == null) return;
    _voorstelVerloopt?.cancel();
    _afgewezen.add(_sleutel(voorstel.route));
    state = nu.kopie(voorstel: () => null);
  }

  /// Twee routes vanaf (bijna) dezelfde plek met dezelfde lengte op 100 m zijn
  /// voor dit doel dezelfde weg.
  static int _sleutel(RouteOptie route) => (route.meters / 100).round();

  Future<void> _herbereken(LocatieFix fix) async {
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
      _voorstelVerloopt?.cancel();
      _nieuweRoute(routes.first, huidig.doelen);
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
