import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../l10n/app_localizations.dart';
import '../models/plaats.dart';
import '../providers/diensten.dart';
import '../providers/instellingen.dart';
import '../providers/planner.dart';
import '../router/app_router.dart';
import '../utils/rechtsklik_stub.dart'
    if (dart.library.js_interop) '../utils/rechtsklik_web.dart';
import '../widgets/kaart.dart';
import '../widgets/route_paneel.dart';

@RoutePage()
class KaartScreen extends ConsumerStatefulWidget {
  const KaartScreen({super.key});

  @override
  ConsumerState<KaartScreen> createState() => _KaartScreenState();
}

class _KaartScreenState extends ConsumerState<KaartScreen> {
  static const _paneelBreedte = 380.0;
  static const _stijlen = ['osm-bright', 'positron', 'dark-matter'];

  MapLibreMapController? _kaart;
  ({Offset plek, LatLng punt})? _menu;
  late final void Function() _stopRechtsklik;

  LatLng? _midden() => _kaart?.cameraPosition?.target;

  @override
  void initState() {
    super.initState();
    _stopRechtsklik = luisterNaarRechtsklik((opKaart, opScherm) async {
      final punt = await _kaart?.toLatLng(opKaart);
      if (punt != null && mounted) _puntMenu(opScherm, punt);
    });
  }

  @override
  void dispose() {
    _stopRechtsklik();
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
    void zet(Plaats plaats) => switch (actie) {
      'van' => planner.zetPunt(0, plaats),
      'naar' => planner.zetPunt(
        ref.read(plannerProvider).punten.length - 1,
        plaats,
      ),
      _ => planner.voegViaToe(plaats),
    };
    // Eerst het kale punt, zodat de route meteen rekent; het adres komt erbij
    // zodra Photon antwoordt -- of niet, en dan blijven het coördinaten.
    zet(Plaats.vanPunt(punt));
    if (actie == 'via') return;
    try {
      final metAdres = await ref.read(photonProvider)?.omgekeerd(punt);
      if (metAdres == null || !mounted) return;
      final punten = ref.read(plannerProvider).punten;
      final index = actie == 'van' ? 0 : punten.length - 1;
      if (punten[index]?.punt == punt) planner.zetPunt(index, metAdres);
    } on Object {
      // Geen adres is geen fout.
    }
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
      punten: planner.punten,
      routes: planner.routes.value ?? const [],
      gekozen: planner.gekozen,
      onRouteGekozen: ref.read(plannerProvider.notifier).kies,
      onLangIngedrukt: _puntMenu,
      onController: (controller) => _kaart = controller,
      rand: breed
          ? const EdgeInsets.only(left: _paneelBreedte)
          : EdgeInsets.only(bottom: hoogte * 0.35),
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
                  onSelected: (stijl) => ref
                      .read(instellingenProvider.notifier)
                      .wijzig(instellingen.kopie(stijl: stijl)),
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
                  ],
                ),
                IconButton(
                  tooltip: l.noordBoven,
                  icon: const _Rondje(Icons.explore_outlined),
                  onPressed: () =>
                      _kaart?.animateCamera(CameraUpdate.bearingTo(0)),
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

    return Scaffold(
      body: breed
          ? Stack(
              children: [
                kaart,
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
                ),
                knoppen,
                ?menu,
              ],
            )
          : Stack(
              children: [
                kaart,
                knoppen,
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
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
                ?menu,
              ],
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
