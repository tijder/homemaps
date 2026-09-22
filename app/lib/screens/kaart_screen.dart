import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../l10n/app_localizations.dart';
import '../models/plaats.dart';
import '../models/profiel.dart';
import '../providers/diensten.dart';
import '../providers/instellingen.dart';
import '../providers/planner.dart';
import '../router/app_router.dart';
import '../utils/muis_stub.dart'
    if (dart.library.js_interop) '../utils/muis_web.dart';
import '../widgets/kaart.dart';
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
  static const _stijlen = ['osm-bright', 'positron', 'dark-matter'];

  /// De keuze in het lagenmenu die de verkeerslaag aan- of uitzet.
  static const _verkeer = 'verkeer';

  MapLibreMapController? _kaart;
  ({Offset plek, LatLng punt})? _menu;
  ({Offset plek, Map<String, dynamic> info})? _melding;
  late final void Function() _stopMuis;

  LatLng? _midden() => _kaart?.cameraPosition?.target;

  @override
  void initState() {
    super.initState();
    _stopMuis = koppelMuis((opKaart, opScherm) async {
      final punt = await _kaart?.toLatLng(opKaart);
      if (punt != null && mounted) _puntMenu(opScherm, punt);
    });
  }

  @override
  void dispose() {
    _stopMuis();
    super.dispose();
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

    final planner = ref.watch(plannerProvider);
    final instellingen = ref.watch(instellingenProvider);
    final breed = MediaQuery.sizeOf(context).width >= 800;
    final hoogte = MediaQuery.sizeOf(context).height;

    final kaart = Kaart(
      stijlUrl: config.stijlUrl(instellingen.stijl),
      start: start,
      punten: [for (final punt in planner.punten) punt.plaats],
      gevonden: planner.gevonden,
      beeldVersie: planner.beeldVersie,
      onPuntVersleept: _versleept,
      routes: planner.routes.value ?? const [],
      gekozen: planner.gekozen,
      onRouteGekozen: ref.read(plannerProvider.notifier).kies,
      onLangIngedrukt: _puntMenu,
      onController: (controller) => _kaart = controller,
      verkeer: ref.watch(verkeerProvider).value,
      // Een file zegt de fietser en de wandelaar niets; een dichte weg wel.
      toonVertraging: instellingen.profiel == Profiel.auto,
      onVerkeerGetikt: (scherm, info) => setState(
        () => _melding = (plek: Offset(scherm.x, scherm.y), info: info),
      ),
      rand: breed
          ? const EdgeInsets.only(left: _paneelBreedte)
          : EdgeInsets.only(
              top: planner.routeModus ? 0 : 72,
              bottom: planner.routeModus ? hoogte * 0.35 : 0,
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
                  onSelected: (keuze) => ref
                      .read(instellingenProvider.notifier)
                      .wijzig(
                        keuze == _verkeer
                            ? instellingen.kopie(
                                verkeerOpKaart: !instellingen.verkeerOpKaart,
                              )
                            : instellingen.kopie(stijl: keuze),
                      ),
                  itemBuilder: (_) => [
                    for (final (stijl, naam) in [
                      (_stijlen[0], l.stijlKaart),
                      (_stijlen[1], l.stijlLicht),
                      (_stijlen[2], l.stijlDonker),
                    ])
                      PopupMenuItem(
                        value: stijl,
                        child: PointerInterceptor(child: Text(naam)),
                      ),
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem(
                      value: _verkeer,
                      checked: instellingen.verkeerOpKaart,
                      child: PointerInterceptor(child: Text(l.verkeerOpKaart)),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: l.noordBoven,
                  icon: const _Rondje(Icons.explore_outlined),
                  onPressed: _zetRecht,
                ),
                IconButton(
                  tooltip: l.instellingen,
                  icon: const _Rondje(Icons.settings_outlined),
                  onPressed: () =>
                      context.router.push(const InstellingenRoute()),
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

    return Scaffold(
      body: Stack(
        children: [
          kaart,
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
                  child: SafeArea(child: RoutePaneel(nabij: _midden)),
                ),
              ),
            )
          else
            DraggableScrollableSheet(
              initialChildSize: 0.35,
              minChildSize: 0.12,
              maxChildSize: 0.92,
              snap: true,
              builder: (context, scroll) => PointerInterceptor(
                child: Material(
                  elevation: 8,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // Het greepje: laat zien dat het paneel te verslepen is.
                      Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: RoutePaneel(nabij: _midden, scroll: scroll),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Op een smal scherm staat de zoekbalk bovenaan; de knoppen schuiven
          // eronder.
          Padding(
            padding: EdgeInsets.only(
              top: !breed && !planner.routeModus ? 64 : 0,
            ),
            child: knoppen,
          ),
          ?melding,
          ?menu,
        ],
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
                      gevonden.naam,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (gevonden.omschrijving.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(gevonden.omschrijving),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: acties.startRoute,
                      icon: const Icon(Icons.directions),
                      label: Text(l.route),
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
              onPressed: () => context.router.push(const InstellingenRoute()),
              child: Text(l.instellingen),
            ),
          ],
        ),
      ),
    );
  }
}
