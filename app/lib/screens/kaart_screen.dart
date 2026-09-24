import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../l10n/app_localizations.dart';
import '../models/dawarich.dart';
import '../models/plaats.dart';
import '../models/profiel.dart';
import '../models/route.dart';
import '../navigatie/afslag_pijl.dart';
import '../navigatie/navigatie_provider.dart';
import '../navigatie/simulatie.dart';
import '../providers/dawarich.dart';
import '../providers/diensten.dart';
import '../providers/instellingen.dart';
import '../providers/locatie.dart';
import '../providers/locatie_delen.dart';
import '../providers/planner.dart';
import '../providers/plekken.dart';
import '../utils/afstand.dart';
import '../utils/geo_link.dart';
import '../utils/opmaak.dart' show geleden;
import '../router/app_router.dart';
import 'instellingen/categorie.dart';
import '../utils/muis_stub.dart'
    if (dart.library.js_interop) '../utils/muis_web.dart';
import '../utils/testhaak_stub.dart'
    if (dart.library.js_interop) '../utils/testhaak_web.dart';
import '../widgets/stappen_lijst.dart';
import '../widgets/kaart.dart';
import '../widgets/langs_route.dart';
import '../widgets/locatie_reden.dart';
import '../widgets/navigatie_balk.dart';
import '../widgets/route_paneel.dart';
import '../widgets/verkeer_melding.dart';
import '../widgets/zoekveld.dart';

@RoutePage()
class KaartScreen extends ConsumerStatefulWidget {
  const KaartScreen({super.key});

  @override
  ConsumerState<KaartScreen> createState() => _KaartScreenState();
}

class _KaartScreenState extends ConsumerState<KaartScreen> {
  static const _paneelBreedte = 380.0;

  /// De keuzes in het lagenmenu die de verkeerslaag en je locatie aan- of
  /// uitzetten.
  static const _verkeer = 'verkeer';
  static const _locatie = 'locatie';

  /// Keuzes voor dag of nacht bij de stijl "Kaart": `thema:` + [KaartThema].
  static const _thema = 'thema:';

  MapLibreMapController? _kaart;
  ({Offset plek, LatLng punt})? _menu;
  ({Offset plek, Map<String, dynamic> info})? _melding;
  late final void Function() _stopMuis;

  /// Tijdens navigatie: rijdt de camera mee? Even niet als je zelf aan de kaart
  /// zit; na [_hervatNa] zonder aanraking weer wel.
  bool _volgt = true;
  Timer? _hervat;
  static const _hervatNa = Duration(seconds: 10);

  /// Zo dicht bij de volgende afslag staat de pijl op de kaart.
  static const _pijlBinnen = 1000.0;

  /// De pijl van de laatste afslag; pas een nieuwe bij een andere afslag of
  /// route, zodat de kaart hem niet bij elke fix opnieuw tekent.
  ({RouteOptie route, int index, List<LatLng>? lijn})? _pijl;

  /// Het bottomsheet op een smal scherm: laag (alleen de samenvatting en de
  /// gekozen route), half (alle routes en Start) of bijna vol.
  final _sheet = DraggableScrollableController();
  static const _sheetHalf = 0.45, _sheetVol = 0.92;
  double _sheetFractie = _sheetHalf;

  /// Hoog genoeg voor het greepje, de samenvattingsregel en één route.
  double _sheetLaag(double hoogte) => (205 / hoogte).clamp(0.12, 0.3);

  /// Met het scherm uit (navigatie loopt door) heeft meedraaien geen zin.
  bool _zichtbaar = true;
  late final AppLifecycleListener _levensloop;
  StreamSubscription<Uri>? _links;

  LatLng? _midden() => _kaart?.cameraPosition?.target;

  /// Het kaartje van het gevolgde familielid; zolang dat openstaat, volgt de
  /// kaart hem.
  Plaats? _familiePlaats;

  /// Je schoof zelf aan de kaart: het kaartje blijft bijwerken, de camera
  /// niet, tot "Volgen".
  bool _familieVrij = false;

  Plaats _alsPlaats(FamilieLocatie lid, AppLocalizations l) => Plaats(
    naam: lid.email,
    omschrijving: [
      geleden(l, DateTime.now().difference(lid.tijd)),
      if (lid.batterij case final procent?) l.familieBatterij(procent),
    ].join(' · '),
    punt: lid.punt,
  );

  /// Op een familielid getikt: zijn kaartje, en de kaart volgt hem.
  void _volgFamilie(FamilieLocatie lid) {
    final plaats = _alsPlaats(lid, AppLocalizations.of(context));
    setState(() {
      _familiePlaats = plaats;
      _familieVrij = false;
    });
    ref.read(gevolgdLidProvider.notifier).volg(lid.userId);
    ref.read(plannerProvider.notifier).toonPlaats(plaats);
  }

  void _stopFamilie() {
    _familiePlaats = null;
    ref.read(gevolgdLidProvider.notifier).stop();
  }

  /// Nieuwe plekken van de familie: het gevolgde lid bijwerken.
  void _familieBijgewerkt(List<FamilieLocatie> familie) {
    final id = ref.read(gevolgdLidProvider);
    if (id == null) return;
    final lid = familie.where((f) => f.userId == id).firstOrNull;
    // Deelt niet meer, of de familie staat uit.
    if (lid == null) {
      _stopFamilie();
      return;
    }
    final plaats = _alsPlaats(lid, AppLocalizations.of(context));
    _familiePlaats = plaats;
    ref.read(plannerProvider.notifier).vervangPlaats(plaats);
    if (!_familieVrij) {
      _kaart?.animateCamera(CameraUpdate.newLatLng(lid.punt));
    }
  }

  @override
  void initState() {
    super.initState();
    _stopMuis = koppelMuis((opKaart, opScherm) async {
      final punt = await _kaart?.toLatLng(opKaart);
      if (punt != null && mounted) _puntMenu(opScherm, punt);
    }, bijAanraking: _zelfBewogen);
    // Een adres of punt uit een andere app (agenda, contacten, een website):
    // `geo:` en `google.navigation:`. Ook de link waarmee de app gestart is.
    if (!kIsWeb) _links = AppLinks().uriLinkStream.listen(_linkOntvangen);
    // Op het web: ?naar=lat,lon (en eventueel &van=lat,lon) opent meteen de
    // route, om een route als link te delen. Met ?simulatie= gaat ook de
    // locatie vanzelf aan (voor de browsertoetsen).
    if (kIsWeb) WidgetsBinding.instance.addPostFrameCallback((_) => _uitUrl());
    _levensloop = AppLifecycleListener(
      onHide: () => setState(() => _zichtbaar = false),
      onShow: () => setState(() => _zichtbaar = true),
    );
  }

  @override
  void dispose() {
    _stopMuis();
    _hervat?.cancel();
    _levensloop.dispose();
    _links?.cancel();
    _sheet.dispose();
    super.dispose();
  }

  Future<void> _uitUrl() async {
    final parameters = Uri.base.queryParameters;
    LatLng? punt(String? tekst) {
      final delen = tekst?.split(',');
      if (delen == null || delen.length != 2) return null;
      final lat = double.tryParse(delen[0]), lon = double.tryParse(delen[1]);
      return lat == null || lon == null ? null : LatLng(lat, lon);
    }

    if (ref.read(locatieBronProvider) is SimulatieBron) {
      await ref.read(locatieProvider.notifier).zetAan();
    }
    final naar = punt(parameters['naar']);
    if (naar == null || !mounted) return;
    final planner = ref.read(plannerProvider.notifier);
    planner.toonPlaats(Plaats.vanPunt(naar));
    planner.startRoute();
    if (punt(parameters['van']) case final van?) {
      planner.zetVan(Plaats.vanPunt(van));
    }
  }

  void _zelfBewogen() {
    if (_familiePlaats != null && !_familieVrij) {
      setState(() => _familieVrij = true);
    }
    if (ref.read(navigatieProvider) == null) return;
    _hervat?.cancel();
    _hervat = Timer(_hervatNa, () {
      if (mounted) setState(() => _volgt = true);
    });
    if (_volgt) setState(() => _volgt = false);
  }

  /// "Start": locatie zo nodig aan, dan navigeren naar de punten na "van". Staat
  /// "van" ergens anders dan jij, dan rekent de navigatie vanzelf opnieuw vanaf
  /// waar je bent.
  Future<void> _startNavigatie(RouteOptie route) async {
    final l = AppLocalizations.of(context);
    // De knop kan alleen met een bekende plek; zie RoutePaneel.
    if (ref.read(locatieProvider).fix == null) {
      _meldLocatieProbleem();
      return;
    }
    final doelen = [
      for (final punt in ref.read(plannerProvider).punten.skip(1)) ?punt.plaats,
    ];
    if (doelen.isEmpty) return;
    // Android 13+: zonder deze toestemming loopt de navigatie met het scherm uit
    // ook, maar zonder zichtbare melding. Eén keer vragen; weigeren mag.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Permission.notification.request();
      if (!mounted) return;
    }
    setState(() => _volgt = true);
    await ref
        .read(navigatieProvider.notifier)
        .start(
          route: route,
          doelen: doelen,
          teksten: NavTeksten.uit(
            l,
            ref.read(plannerProvider.notifier).taal,
            doelen.last.weergave(l),
            delen: ref.read(deelInstellingenProvider).aan,
          ),
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Valhalla kent 'nl-NL' en 'en-US'; al het andere valt terug op Engels.
    final taal = Localizations.localeOf(context).languageCode;
    ref.read(plannerProvider.notifier).taal = taal == 'nl' ? 'nl-NL' : 'en-US';
  }

  /// Het menu "van hier / hierheen / als tussenpunt": rechtermuisknop op het web,
  /// lang indrukken op Android. Geen showMenu: de kaart is op het web een los
  /// HTML-element dat de muis afvangt, dus Flutters eigen menu kreeg de klik
  /// ernaast nooit te zien -- het sloot niet, en elke rechtsklik zette er een bij.
  /// Dit is één stuk state, dus er is er altijd hooguit één.
  void _puntMenu(Point<double> scherm, LatLng punt) =>
      setState(() => _menu = (plek: Offset(scherm.x, scherm.y), punt: punt));

  Future<void> _kies(String actie, LatLng punt) async {
    setState(() => _menu = null);
    final planner = ref.read(plannerProvider.notifier);
    // Geen volgBeeld: je klikte op de kaart, dus het punt is al in beeld.
    switch (actie) {
      case 'van':
        planner.zetVan(Plaats.vanPunt(punt), volgBeeld: false);
      case 'naar':
        planner.zetNaar(Plaats.vanPunt(punt), volgBeeld: false);
      default:
        planner.voegViaToe(Plaats.vanPunt(punt));
    }
    await _zoekAdresErbij(punt);
  }

  /// Een punt dat op de kaart is gezet of versleept heet eerst naar zijn
  /// coördinaten, zodat de route meteen rekent; het adres komt erbij zodra Photon
  /// antwoordt -- of niet, en dan blijven het coördinaten.
  Future<void> _zoekAdresErbij(LatLng punt) async {
    try {
      final metAdres = await ref.read(photonProvider)?.omgekeerd(punt);
      if (metAdres == null || !mounted) return;
      final punten = ref.read(plannerProvider).punten;
      final index = punten.indexWhere((p) => p.plaats?.punt == punt);
      if (index < 0) return; // intussen alweer verplaatst
      // Alleen de naam verandert; de route hoeft niet opnieuw.
      ref.read(plannerProvider.notifier).hernoem(index, metAdres);
    } on Object {
      // Geen adres is geen fout.
    }
  }

  /// Noorden boven én plat: `bearingTo(0)` alleen laat een gekantelde kaart scheef
  /// staan. Plek en zoom blijven wat ze zijn.
  void _zetRecht() {
    final nu = _kaart?.cameraPosition;
    if (nu == null) return;
    _kaart!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: nu.target, zoom: nu.zoom, bearing: 0, tilt: 0),
      ),
    );
  }

  /// De knop "Mijn locatie": vraagt zo nodig toestemming en vliegt erheen.
  Future<void> _naarMijnLocatie() async {
    final fix = await ref.read(locatieProvider.notifier).zetAan();
    if (!mounted) return;
    if (fix == null) {
      _meldLocatieProbleem();
      return;
    }
    final zoom = max(_kaart?.cameraPosition?.zoom ?? 0, 15.0);
    await _kaart?.animateCamera(CameraUpdate.newLatLngZoom(fix.punt, zoom));
  }

  Future<void> _linkOntvangen(Uri uri) async {
    final verzoek = leesGeoLink(uri);
    if (verzoek == null || !mounted) return;
    final l = AppLocalizations.of(context);
    if (ref.read(navigatieProvider) != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.eerstStoppen)));
      return;
    }
    Plaats? plaats;
    if (verzoek.punt case final punt?) {
      plaats = verzoek.label == null
          ? Plaats.vanPunt(punt)
          : Plaats(naam: verzoek.label!, punt: punt);
    } else if (verzoek.zoek case final zoek?) {
      try {
        final gevonden = await ref
            .read(photonProvider)
            ?.zoek(
              zoek,
              nabij: ref.read(locatieProvider).fix?.punt ?? _midden(),
            );
        plaats = gevonden?.firstOrNull;
      } on Object {
        plaats = null;
      }
      if (!mounted) return;
      if (plaats == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.nietGevonden(zoek))));
        return;
      }
    }
    if (plaats == null) return;
    final planner = ref.read(plannerProvider.notifier);
    planner.naarZoeken();
    planner.toonPlaats(plaats);
    if (verzoek.navigeer) planner.startRoute();
    // Een kaal punt krijgt zijn adres erbij, zodra Photon het weet.
    if (verzoek.punt != null && verzoek.label == null) {
      try {
        final metAdres = await ref.read(photonProvider)?.omgekeerd(plaats.punt);
        if (metAdres != null && mounted) {
          final nu = ref.read(plannerProvider);
          if (nu.gevonden?.punt == plaats.punt && !nu.routeModus) {
            planner.toonPlaats(metAdres);
          }
        }
      } on Object {
        // Dan blijven het coördinaten.
      }
    }
  }

  /// Locatie aan vanuit het routepaneel (voor navigatie): zonder de kaart te
  /// verschuiven.
  Future<void> _zetLocatieAan() async {
    final fix = await ref.read(locatieProvider.notifier).zetAan();
    if (fix == null && mounted) _meldLocatieProbleem();
  }

  /// "Mijn locatie" in een zoekvakje.
  Future<Plaats?> _mijnLocatieAlsPlaats() async {
    final fix = await ref.read(locatieProvider.notifier).zetAan();
    if (!mounted) return null;
    if (fix == null) {
      _meldLocatieProbleem();
      return null;
    }
    return Plaats.hier(fix.punt);
  }

  /// Waarom er geen locatie is, en waar je dat verhelpt. Op het web kan de app
  /// de instellingen van de browser niet openen; dan alleen de uitleg. iOS
  /// opent alleen de instellingen van de app zelf, niet die van locatie.
  void _meldLocatieProbleem() {
    final l = AppLocalizations.of(context);
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final stand = ref.read(locatieProvider).stand;
    final tekst = locatieReden(l, stand) ?? l.locatieNietGevonden;
    final openen = switch (stand) {
      LocatieStand.permanentGeweigerd when android || ios =>
        Geolocator.openAppSettings,
      LocatieStand.dienstUit when android => Geolocator.openLocationSettings,
      _ => null,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tekst),
        action: openen == null
            ? null
            : SnackBarAction(label: l.instellingen, onPressed: openen),
      ),
    );
  }

  void _versleept(int index, LatLng punt) {
    ref
        .read(plannerProvider.notifier)
        .zetPunt(index, Plaats.vanPunt(punt), volgBeeld: false);
    _zoekAdresErbij(punt);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final config = ref.watch(appConfigProvider);
    if (config == null) return const _ServerNodig();

    // De kaart kan zijn beginpositie maar één keer krijgen; even wachten op de
    // TileJSON (hooguit 5 s) is beter dan openen boven het verkeerde land.
    final start = ref.watch(kaartStartProvider).value;
    if (start == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    ref.listen(familieLocatiesProvider, (_, familie) {
      _familieBijgewerkt(familie);
    });
    // Een ander kaartje, of een route: niet meer volgen.
    ref.listen(plannerProvider, (_, p) {
      if (_familiePlaats != null &&
          (p.routeModus || !identical(p.gevonden, _familiePlaats))) {
        _stopFamilie();
      }
    });

    final planner = ref.watch(plannerProvider);
    final instellingen = ref.watch(instellingenProvider);
    final locatieStand = ref.watch(locatieProvider.select((t) => t.stand));
    final locatieAan =
        locatieStand == LocatieStand.aan ||
        locatieStand == LocatieStand.zoekt ||
        locatieStand == LocatieStand.nietGevonden;
    final breed = MediaQuery.sizeOf(context).width >= 800;
    final hoogte = MediaQuery.sizeOf(context).height;

    final nav = ref.watch(navigatieProvider);
    final fix = ref.watch(locatieProvider.select((t) => t.fix));
    if (kIsWeb && ref.read(locatieBronProvider) is SimulatieBron) {
      final stand = nav?.stand;
      publiceerTestStand({
        'locatie': ref.read(locatieProvider).stand.name,
        'routeModus': planner.routeModus,
        'routes': planner.routes.value?.length ?? 0,
        'navigeert': nav != null,
        'aangekomen': nav?.aangekomen ?? false,
        'volgende': stand == null
            ? null
            : nav!.route.manoeuvres[stand.volgende].instructie,
        'restMeters': stand?.restMeters.round(),
        'vanRoute': stand?.vanRoute,
      });
    }
    // Tijdens navigatie staat het puntje op de weg zolang je op de route rijdt,
    // zoals je dat van een navigatiesysteem gewend bent.
    final stand = nav?.stand;
    final opWeg =
        nav != null && stand != null && fix != null && stand.afwijking < 30
        ? LocatieFix(
            punt: stand.opRoute,
            tijd: fix.tijd,
            nauwkeurigheid: fix.nauwkeurigheid,
            koers: stand.routeKoers,
            snelheid: fix.snelheid,
          )
        : fix;

    // 's Nachts (vast, of als de telefoon op donker staat) de nachtversie van
    // de gewone kaart. Tot die er is (of als hij niet lukt) de gewone.
    final stijlUrl = config.stijlUrl(instellingen.stijl);
    final isNacht = switch (instellingen.thema) {
      KaartThema.automatisch =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
      KaartThema.dag => false,
      KaartThema.nacht => true,
    };
    final nacht = instellingen.stijl == KaartStijl.kaart.id && isNacht
        ? ref.watch(nachtStijlProvider(stijlUrl)).value
        : null;
    final kaart = Kaart(
      stijlUrl: nacht ?? stijlUrl,
      start: start,
      punten: nav != null
          ? [null, ...nav.doelen]
          : [for (final punt in planner.punten) punt.plaats],
      gevonden: nav != null ? null : planner.gevonden,
      beeldVersie: planner.beeldVersie,
      onPuntVersleept: nav != null ? (_, _) {} : _versleept,
      // Tijdens navigatie de route, en een voorgestelde snellere grijs ernaast.
      routes: nav != null
          ? [nav.route, ?nav.voorstel?.route]
          : planner.routes.value ?? const [],
      gekozen: nav != null ? 0 : planner.gekozen,
      onRouteGekozen: nav != null
          // De grijze lijn aantikken is "Nemen".
          ? (i) {
              if (i == 1) ref.read(navigatieProvider.notifier).neemVoorstel();
            }
          : ref.read(plannerProvider.notifier).kies,
      onLangIngedrukt: _puntMenu,
      onController: (controller) => _kaart = controller,
      locatie: opWeg,
      volg:
          nav != null &&
              _volgt &&
              _zichtbaar &&
              opWeg != null &&
              !nav.aangekomen
          ? (
              punt: opWeg.punt,
              koers: opWeg.koers ?? stand?.routeKoers ?? 0,
              snelheid: opWeg.snelheid ?? 0,
            )
          : null,
      navigeert: nav != null && !nav.aangekomen,
      gereden: nav != null && stand != null
          ? [...nav.route.punten.take(stand.segment + 1), stand.opRoute]
          : null,
      pijl: _pijlVoor(nav),
      onZelfBewogen: _zelfBewogen,
      verkeer: ref.watch(verkeerProvider).value,
      // Een file zegt de fietser en de wandelaar niets; een dichte weg wel.
      toonVertraging: instellingen.profiel == Profiel.auto,
      onVerkeerGetikt: (scherm, info) => setState(
        () => _melding = (plek: Offset(scherm.x, scherm.y), info: info),
      ),
      familie: ref.watch(familieLocatiesProvider),
      // Een familielid is een plek als een zoekresultaat, met "Route" erheen,
      // en de kaart volgt hem.
      onFamilieGetikt: nav != null ? null : _volgFamilie,
      rand: breed
          ? const EdgeInsets.only(left: _paneelBreedte)
          : EdgeInsets.only(
              top: planner.routeModus ? 0 : 72,
              bottom: planner.routeModus ? hoogte * _sheetFractie : 0,
            ),
    );

    final knoppen = SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: PointerInterceptor(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<String>(
                  tooltip: l.kaartstijl,
                  icon: const _Rondje(Icons.layers_outlined),
                  initialValue: instellingen.stijl,
                  onSelected: (keuze) {
                    if (keuze == _locatie) {
                      locatieAan
                          ? ref.read(locatieProvider.notifier).zetUit()
                          : _naarMijnLocatie();
                      return;
                    }
                    ref
                        .read(instellingenProvider.notifier)
                        .wijzig(
                          keuze == _verkeer
                              ? instellingen.kopie(
                                  verkeerOpKaart: !instellingen.verkeerOpKaart,
                                )
                              : keuze.startsWith(_thema)
                              ? instellingen.kopie(
                                  thema: KaartThema.values.byName(
                                    keuze.substring(_thema.length),
                                  ),
                                )
                              : instellingen.kopie(stijl: keuze),
                        );
                  },
                  itemBuilder: (_) => [
                    for (final stijl in KaartStijl.values)
                      PopupMenuItem(
                        value: stijl.id,
                        child: PointerInterceptor(child: Text(stijl.naam(l))),
                      ),
                    if (instellingen.stijl == KaartStijl.kaart.id) ...[
                      const PopupMenuDivider(),
                      for (final thema in KaartThema.values)
                        CheckedPopupMenuItem(
                          value: '$_thema${thema.name}',
                          checked: instellingen.thema == thema,
                          child: PointerInterceptor(child: Text(thema.naam(l))),
                        ),
                    ],
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem(
                      value: _verkeer,
                      checked: instellingen.verkeerOpKaart,
                      child: PointerInterceptor(child: Text(l.verkeerOpKaart)),
                    ),
                    CheckedPopupMenuItem(
                      value: _locatie,
                      checked: locatieAan,
                      child: PointerInterceptor(child: Text(l.mijnLocatie)),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: l.mijnLocatie,
                  icon: _Rondje(switch (locatieStand) {
                    LocatieStand.aan => Icons.my_location,
                    LocatieStand.uit ||
                    LocatieStand.zoekt => Icons.location_searching,
                    LocatieStand.nietGevonden => Icons.gps_not_fixed,
                    _ => Icons.location_disabled,
                  }),
                  onPressed: _naarMijnLocatie,
                ),
                IconButton(
                  tooltip: l.noordBoven,
                  icon: const _Rondje(Icons.explore_outlined),
                  onPressed: _zetRecht,
                ),
                IconButton(
                  tooltip: l.instellingen,
                  icon: const _Rondje(Icons.settings_outlined),
                  onPressed: () => context.router.push(InstellingenRoute()),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final menu = _menu == null ? null : _menuLaag(context, _menu!);
    final melding = _melding == null
        ? null
        : _meldingLaag(context, _melding!.plek, _melding!.info);

    // Mag de terugknop de app uit? Alleen als er niets meer te sluiten is.
    final magWeg =
        nav == null &&
        !planner.routeModus &&
        planner.gevonden == null &&
        _menu == null &&
        _melding == null;
    Widget terugknop(Widget kind) => PopScope(
      canPop: magWeg,
      onPopInvokedWithResult: (weg, _) {
        if (!weg) _terug();
      },
      child: kind,
    );

    if (nav != null) {
      return terugknop(
        Scaffold(
          body: Stack(children: [kaart, _navigatieLaag(nav, breed), ?melding]),
        ),
      );
    }

    return terugknop(
      Scaffold(
        body: Stack(
          children: [
            kaart,
            // Op een smal scherm staat de zoekbalk bovenaan; de knoppen schuiven
            // eronder. Vóór de panelen in de stapel: de suggesties van de
            // zoekbalk en het opgetrokken sheet gaan eroverheen, niet eronder.
            Padding(
              padding: EdgeInsets.only(
                top: !breed && !planner.routeModus ? 64 : 0,
              ),
              child: knoppen,
            ),
            if (!planner.routeModus)
              _zoekscherm(context, planner, breed)
            else if (breed)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _paneelBreedte,
                // De kaart is op het web een los HTML-element onder Flutter. Zonder
                // interceptor schijnt zijn sleep-cursor door het paneel heen.
                child: PointerInterceptor(
                  child: Material(
                    elevation: 4,
                    child: SafeArea(
                      child: RoutePaneel(
                        nabij: _midden,
                        mijnLocatie: _mijnLocatieAlsPlaats,
                        onNavigeer: _startNavigatie,
                        onLocatieAan: _zetLocatieAan,
                      ),
                    ),
                  ),
                ),
              )
            else
              NotificationListener<DraggableScrollableNotification>(
                onNotification: (melding) {
                  // Voor het in beeld brengen van de route: boven het sheet.
                  _sheetFractie = melding.extent;
                  // Helemaal naar beneden geveegd: dicht, terug naar zoeken.
                  if (melding.extent < 0.02) _sluitSheet();
                  return false;
                },
                child: DraggableScrollableSheet(
                  controller: _sheet,
                  initialChildSize: _sheetHalf,
                  // Onder de lage stand is dicht: tot 0 kan het sheet mee
                  // omlaag, en dan sluit het.
                  minChildSize: 0,
                  maxChildSize: _sheetVol,
                  snap: true,
                  snapSizes: [_sheetLaag(hoogte), _sheetHalf],
                  builder: (context, scroll) => PointerInterceptor(
                    child: Material(
                      elevation: 8,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _greep(hoogte),
                          Expanded(
                            // Ook met de muis te slepen (een smal browservenster);
                            // Flutter staat dat standaard alleen met een vinger
                            // toe.
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(
                                    dragDevices: {
                                      ...ScrollConfiguration.of(context)
                                          .dragDevices,
                                      PointerDeviceKind.mouse,
                                    },
                                  ),
                              child: RoutePaneel(
                                nabij: _midden,
                                mijnLocatie: _mijnLocatieAlsPlaats,
                                onNavigeer: _startNavigatie,
                                onLocatieAan: _zetLocatieAan,
                                scroll: scroll,
                                compact: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ?melding,
            ?menu,
          ],
        ),
      ),
    );
  }

  /// Het beginscherm: één zoekbalk, en na een keuze een kaartje van de plaats met
  /// de knop "Route". Pas die knop opent het routescherm.
  Widget _zoekscherm(BuildContext context, PlannerState planner, bool breed) {
    final l = AppLocalizations.of(context);
    final acties = ref.read(plannerProvider.notifier);
    final gevonden = planner.gevonden;
    final balk = PointerInterceptor(
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Zoekveld(
            zwevend: true,
            label: l.zoekHier,
            pictogram: Icons.search,
            plaats: gevonden,
            nabij: _midden,
            onGekozen: acties.toonPlaats,
            mijnLocatie: _mijnLocatieAlsPlaats,
            onGewist: acties.sluitPlaats,
          ),
        ),
      ),
    );
    final kaartje = gevonden == null
        ? null
        : PointerInterceptor(
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(16),
              // Volle breedte: de interceptor eromheen geeft de breedte van de
              // kolom niet door, en dan krimpt het kaartje tot zijn tekst.
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gevonden.weergave(l),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (gevonden.omschrijving.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(gevonden.omschrijving),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: acties.startRoute,
                          icon: const Icon(Icons.directions),
                          label: Text(l.route),
                        ),
                        if (identical(gevonden, _familiePlaats))
                          _familieVrij
                              ? OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() => _familieVrij = false);
                                    _kaart?.animateCamera(
                                      CameraUpdate.newLatLng(gevonden.punt),
                                    );
                                  },
                                  icon: const Icon(Icons.my_location),
                                  label: Text(l.familieVolgen),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.my_location, size: 18),
                                    const SizedBox(width: 4),
                                    Text(l.familieVolgt),
                                  ],
                                )
                        else if (!gevonden.mijnLocatie) ...[
                          _BewaarKnop(
                            plaats: gevonden,
                            huidig: ref.watch(plekkenProvider).thuis,
                            pictogram: Icons.home_outlined,
                            label: l.alsThuis,
                            bewaard: l.thuis,
                            onBewaar: ref
                                .read(plekkenProvider.notifier)
                                .zetThuis,
                          ),
                          _BewaarKnop(
                            plaats: gevonden,
                            huidig: ref.watch(plekkenProvider).werk,
                            pictogram: Icons.work_outline,
                            label: l.alsWerk,
                            bewaard: l.werk,
                            onBewaar: ref
                                .read(plekkenProvider.notifier)
                                .zetWerk,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: breed
            ? Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: _paneelBreedte - 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [balk, const SizedBox(height: 12), ?kaartje],
                  ),
                ),
              )
            // Smal: de balk boven, het kaartje onder -- de kaart ertussen blijft
            // vrij.
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [balk, const Spacer(), ?kaartje],
              ),
      ),
    );
  }

  /// Een vlak over het hele scherm dat de muis van de kaart afhoudt, met het menu
  /// erop. Ernaast klikken sluit het; ernaast rechtsklikken verplaatst het.
  Widget _menuLaag(BuildContext context, ({Offset plek, LatLng punt}) menu) {
    final l = AppLocalizations.of(context);
    final scherm = MediaQuery.sizeOf(context);
    const breedte = 220.0, hoogte = 3 * 48.0 + 16;
    return Positioned.fill(
      child: PointerInterceptor(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _menu = null),
          onSecondaryTapDown: (details) async {
            // Dit vlak ligt precies over de kaart, dus de plek erop is ook de plek
            // op de kaart.
            final plek = Point(
              details.localPosition.dx,
              details.localPosition.dy,
            );
            final punt = await _kaart?.toLatLng(plek);
            if (punt != null && mounted) _puntMenu(plek, punt);
          },
          child: Stack(
            children: [
              Positioned(
                // Binnen beeld blijven, ook bij een klik in de hoek.
                left: min(menu.plek.dx, scherm.width - breedte - 8),
                top: min(menu.plek.dy, scherm.height - hoogte - 8),
                width: breedte,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (actie, pictogram, tekst) in [
                          ('van', Icons.trip_origin, l.hierVandaan),
                          ('naar', Icons.place, l.hierNaartoe),
                          ('via', Icons.more_vert, l.alsTussenpunt),
                        ])
                          ListTile(
                            dense: true,
                            leading: Icon(pictogram),
                            title: Text(tekst),
                            onTap: () => _kies(actie, menu.punt),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _sluitGepland = false;

  /// Het sheet is dichtgeveegd: na dit frame terug naar zoeken (niet tijdens
  /// de melding zelf, dan wordt het sheet nog opgebouwd).
  void _sluitSheet() {
    if (_sluitGepland) return;
    _sluitGepland = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sluitGepland = false;
      if (!mounted) return;
      _sheetFractie = _sheetHalf;
      ref.read(plannerProvider.notifier).naarZoeken();
    });
  }

  /// De terugknop (Android): eerst wat er open staat dicht, pas daarna de app
  /// uit. Tijdens navigatie niet: de app uit zou de navigatie stoppen.
  void _terug() {
    final planner = ref.read(plannerProvider);
    if (_menu != null || _melding != null) {
      setState(() {
        _menu = null;
        _melding = null;
      });
    } else if (ref.read(navigatieProvider) != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).eerstStoppen)),
        );
    } else if (planner.routeModus) {
      _sheetFractie = _sheetHalf;
      ref.read(plannerProvider.notifier).naarZoeken();
    } else if (planner.gevonden != null) {
      ref.read(plannerProvider.notifier).sluitPlaats();
    }
  }

  /// Het greepje van het sheet. Het sheet zelf schuift alleen mee met zijn
  /// lijst; het greepje zit daarbuiten, dus slepen gaat hier met de hand. Een
  /// tik wisselt tussen half en vol.
  Widget _greep(double hoogte) {
    final lagen = [0.0, _sheetLaag(hoogte), _sheetHalf, _sheetVol];
    void naar(double doel) => _sheet.animateTo(
      doel,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => naar(_sheet.size < 0.6 ? _sheetVol : _sheetHalf),
      onVerticalDragUpdate: (details) => _sheet.jumpTo(
        (_sheet.size - details.primaryDelta! / hoogte).clamp(
          lagen.first,
          lagen.last,
        ),
      ),
      onVerticalDragEnd: (details) {
        // Een flinke veeg gaat door naar de volgende stand; anders de
        // dichtstbijzijnde.
        final snelheid = -(details.primaryVelocity ?? 0) / hoogte;
        final nu = _sheet.size;
        final doel = snelheid.abs() > 0.8
            ? (snelheid > 0
                  ? lagen.firstWhere(
                      (l) => l > nu + 0.01,
                      orElse: () => lagen.last,
                    )
                  : lagen.lastWhere(
                      (l) => l < nu - 0.01,
                      orElse: () => lagen.first,
                    ))
            : lagen.reduce((a, b) => (a - nu).abs() < (b - nu).abs() ? a : b);
        naar(doel);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: SizedBox(
          height: 22,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Boven de instructie, onder aankomst en stop; daartussen blijft de kaart
  /// vrij. Elk blok een eigen interceptor: één over het hele scherm zou de kaart
  /// op het web onbedienbaar maken.
  Widget _navigatieLaag(NavigatieToestand nav, bool breed) {
    final l = AppLocalizations.of(context);
    final acties = ref.read(navigatieProvider.notifier);
    Widget blok(Widget kind) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: PointerInterceptor(child: kind),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: breed
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.stretch,
          children: [
            blok(
              NavigatieKop(
                nav,
                onTap: nav.stand == null || nav.aangekomen
                    ? null
                    : () => _toonStappen(nav),
              ),
            ),
            const Spacer(),
            // Linksonder: snelheid (auto), en "Hervatten" als je zelf
            // rondkijkt.
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (ref.watch(instellingenProvider).profiel == Profiel.auto &&
                      !nav.aangekomen)
                    PointerInterceptor(
                      child: SnelheidBord(
                        limiet: nav.limiet,
                        bron: nav.limietBron,
                        snelheid: nav.fix?.snelheid,
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (!_volgt && !nav.aangekomen)
                    PointerInterceptor(
                      child: FloatingActionButton.extended(
                        onPressed: () {
                          _hervat?.cancel();
                          setState(() => _volgt = true);
                        },
                        icon: const Icon(Icons.navigation),
                        label: Text(l.hervatten),
                      ),
                    ),
                ],
              ),
            ),
            if (nav.voorstel case final voorstel?) ...[
              blok(
                VoorstelKaart(
                  voorstel,
                  onNemen: acties.neemVoorstel,
                  onNegeren: acties.negeerVoorstel,
                ),
              ),
              const SizedBox(height: 8),
            ],
            blok(
              NavigatieVoet(
                nav,
                onStop: () {
                  // Na aankomst is de route af: terug naar een leeg scherm.
                  // Wie eerder stopt, houdt de route om hem te hervatten.
                  if (nav.aangekomen) {
                    ref.read(plannerProvider.notifier).leeg();
                  }
                  acties.stop();
                  _hervat?.cancel();
                },
                onDempen: acties.dempen,
                onZoekLangs: () => _zoekLangsRoute(nav),
                deelt: _deelt(),
                onDelen: () => context.router.push(
                  InstellingenCategorieRoute(
                    categorie: InstellingenCategorie.locatieDelen.pad,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Voor het pictogram in de voet: null als locatie delen uit staat, `true`
  /// als het versturen misgaat (de punten wachten dan in de wachtrij).
  bool? _deelt() {
    if (!ref.watch(deelInstellingenProvider).aan) return null;
    return ref.watch(locatieDelerProvider).fout != null;
  }

  /// De pijl bij de volgende afslag, als die dichtbij is.
  List<LatLng>? _pijlVoor(NavigatieToestand? nav) {
    final stand = nav?.stand;
    if (nav == null ||
        stand == null ||
        nav.aangekomen ||
        nav.herberekent ||
        stand.totVolgende > _pijlBinnen) {
      return null;
    }
    final oud = _pijl;
    if (oud != null &&
        identical(oud.route, nav.route) &&
        oud.index == stand.volgende) {
      return oud.lijn;
    }
    final lijn = afslagPijl(nav.route, stand.volgende);
    _pijl = (route: nav.route, index: stand.volgende, lijn: lijn);
    return lijn;
  }

  /// Tijdens navigatie: de rest van de routebeschrijving, vanaf de volgende
  /// manoeuvre.
  void _toonStappen(NavigatieToestand nav) {
    final stand = nav.stand;
    if (stand == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PointerInterceptor(
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppLocalizations.of(context).instructies,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  StappenLijst(
                    nav.route,
                    vanaf: stand.volgende,
                    totVolgende: stand.totVolgende,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Tijdens navigatie: een stop langs de rest van de route zoeken.
  Future<void> _zoekLangsRoute(NavigatieToestand nav) async {
    final stand = nav.stand;
    final lijn = stand == null
        ? nav.route.punten
        : [stand.opRoute, ...nav.route.punten.skip(stand.segment + 1)];
    final gekozen = await showModalBottomSheet<Plaats>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PointerInterceptor(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SingleChildScrollView(
              child: LangsRouteZoeker(
                lijn: lijn,
                onGekozen: (plaats) => Navigator.of(context).pop(plaats),
              ),
            ),
          ),
        ),
      ),
    );
    if (gekozen == null || !mounted) return;
    ref.read(navigatieProvider.notifier).voegTussenstopToe(gekozen);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).tussenstopToegevoegd(gekozen.naam),
        ),
      ),
    );
  }

  /// Wat er op een aangetikt stuk verkeer aan de hand is, naast de plek van de
  /// tik. Zoals het puntmenu: een vlak over de kaart dat bij een tik sluit.
  Widget _meldingLaag(
    BuildContext context,
    Offset plek,
    Map<String, dynamic> info,
  ) {
    final scherm = MediaQuery.sizeOf(context);
    const breedte = 260.0, hoogte = 140.0;
    return Positioned.fill(
      child: PointerInterceptor(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _melding = null),
          child: Stack(
            children: [
              Positioned(
                left: min(plek.dx + 8, scherm.width - breedte - 8),
                top: min(plek.dy + 8, scherm.height - hoogte - 8),
                width: breedte,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(8),
                  child: VerkeerMelding(info),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Als thuis" op het kaartje van een gevonden plek, zolang er nog geen thuis
/// is. Is er al een, dan niets -- wijzigen gaat via de instellingen -- behalve
/// op het kaartje van thuis zelf: daar een vinkje.
class _BewaarKnop extends StatelessWidget {
  const _BewaarKnop({
    required this.plaats,
    required this.huidig,
    required this.pictogram,
    required this.label,
    required this.bewaard,
    required this.onBewaar,
  });

  final Plaats plaats;
  final Plaats? huidig;
  final IconData pictogram;
  final String label;
  final String bewaard;
  final ValueChanged<Plaats?> onBewaar;

  @override
  Widget build(BuildContext context) {
    final bestaand = huidig;
    if (bestaand == null) {
      return TextButton.icon(
        onPressed: () => onBewaar(plaats),
        icon: Icon(pictogram),
        label: Text(label),
      );
    }
    if (meters(bestaand.punt, plaats.punt) >= 30) {
      return const SizedBox.shrink();
    }
    final kleur = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 18, color: kleur),
          const SizedBox(width: 4),
          Text(bewaard, style: TextStyle(color: kleur)),
        ],
      ),
    );
  }
}

class _Rondje extends StatelessWidget {
  const _Rondje(this.pictogram);

  final IconData pictogram;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    backgroundColor: Theme.of(context).colorScheme.surface,
    foregroundColor: Theme.of(context).colorScheme.onSurface,
    child: Icon(pictogram),
  );
}

/// Android zonder ingestelde server: er valt nog niets te tonen.
class _ServerNodig extends StatelessWidget {
  const _ServerNodig();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 48),
            const SizedBox(height: 12),
            Text(l.serverNodig),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.router.push(
                InstellingenCategorieRoute(
                  categorie: InstellingenCategorie.server.pad,
                ),
              ),
              child: Text(l.instellingen),
            ),
          ],
        ),
      ),
    );
  }
}
