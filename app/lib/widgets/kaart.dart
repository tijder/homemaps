import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/plaats.dart';
import '../models/route.dart';
import '../utils/afstand.dart';

/// De kaart met de routes en de punten erop. Weet niets van de planner: krijgt
/// wat hij moet tekenen en meldt wat er wordt aangetikt.
class Kaart extends StatefulWidget {
  const Kaart({
    super.key,
    required this.stijlUrl,
    required this.start,
    required this.punten,
    required this.gevonden,
    required this.beeldVersie,
    required this.onPuntVersleept,
    required this.routes,
    required this.gekozen,
    required this.onRouteGekozen,
    required this.onLangIngedrukt,
    required this.rand,
    this.onController,
  });

  final String stijlUrl;
  final CameraPosition start;

  /// De punten van de route (van, via's, naar); op de kaart te verslepen.
  final List<Plaats?> punten;

  /// De plaats uit het zoekscherm: een vaste, blauwe stip.
  final Plaats? gevonden;

  /// Loopt op als het resultaat in beeld gebracht moet worden (zie PlannerState).
  final int beeldVersie;
  final void Function(int index, LatLng punt) onPuntVersleept;
  final List<RouteOptie> routes;
  final int gekozen;
  final ValueChanged<int> onRouteGekozen;
  final void Function(Point<double> scherm, LatLng punt) onLangIngedrukt;

  /// De ruimte die het paneel over de kaart legt; de route wordt daarbuiten
  /// in beeld gebracht.
  final EdgeInsets rand;
  final ValueChanged<MapLibreMapController>? onController;

  @override
  State<Kaart> createState() => _KaartState();
}

class _KaartState extends State<Kaart> {
  static const _routeBron = 'routes';
  static const _aansluitBron = 'aansluiting';

  /// Kleiner dan dit is het gat tussen een punt en de weg niet het tonen waard.
  static const _minAansluiting = 15.0;
  static const _lagen = ['route-alt', 'route-rand', 'route'];

  MapLibreMapController? _controller;
  bool _stijlKlaar = false;

  /// Cirkel-id -> index in [Kaart.punten]; de gevonden plaats zit er niet in.
  final _cirkelIndex = <String, int>{};
  int _ingepast = 0;
  int _tekenVolgnummer = 0;

  @override
  void didUpdateWidget(Kaart oud) {
    super.didUpdateWidget(oud);
    if (oud.stijlUrl != widget.stijlUrl) {
      // Een nieuwe stijl gooit alle bronnen en lagen weg; onStyleLoaded zet ze
      // terug.
      _stijlKlaar = false;
      return;
    }
    if (!_stijlKlaar) return;
    if (oud.routes != widget.routes ||
        oud.gekozen != widget.gekozen ||
        // Het scherm bouwt deze lijst elke keer opnieuw; op inhoud vergelijken,
        // anders worden de cirkels bij elke rebuild vervangen.
        !listEquals(oud.punten, widget.punten) ||
        oud.gevonden != widget.gevonden ||
        oud.beeldVersie != widget.beeldVersie) {
      _teken();
    }
  }

  Future<void> _stijlGeladen() async {
    final c = _controller!;
    // De cirkels van de punten zijn annotaties; hun laag bestaat al. De routelijnen
    // moeten daar ónder, anders verdwijnt een punt achter zijn eigen route.
    final onder = c.circleManager?.layerIds.firstOrNull;
    await c.addGeoJsonSource(_routeBron, _leeg);
    await c.addGeoJsonSource(_aansluitBron, _leeg);
    // Alternatieven grijs en onderop; de gekozen route blauw met een witte rand.
    await c.addLineLayer(
      _routeBron,
      'route-alt',
      const LineLayerProperties(
        lineColor: '#78909c',
        lineWidth: 5,
        lineOpacity: 0.8,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'gekozen'],
        false,
      ],
    );
    await c.addLineLayer(
      _routeBron,
      'route-rand',
      const LineLayerProperties(
        lineColor: '#ffffff',
        lineWidth: 9,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'gekozen'],
        true,
      ],
      enableInteraction: false,
    );
    await c.addLineLayer(
      _routeBron,
      'route',
      const LineLayerProperties(
        lineColor: '#1565c0',
        lineWidth: 6,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'gekozen'],
        true,
      ],
    );
    // Van waar je klikte naar waar de route de weg oppakt: Valhalla legt een punt
    // naast de weg op de dichtstbijzijnde weg, en zonder dit lijntje lijkt de
    // route dan zomaar ergens anders te beginnen.
    await c.addLineLayer(
      _aansluitBron,
      'aansluiting',
      const LineLayerProperties(
        lineColor: '#546e7a',
        lineWidth: 3,
        lineDasharray: [0.5, 2],
        lineCap: 'round',
      ),
      enableInteraction: false,
      belowLayerId: onder,
    );
    _stijlKlaar = true;
    _cirkelIndex.clear();
    _ingepast = 0;
    await _teken();
  }

  static const _leeg = {'type': 'FeatureCollection', 'features': <dynamic>[]};

  Future<void> _teken() async {
    final c = _controller;
    if (c == null || !_stijlKlaar) return;
    // Twee updates kort na elkaar: alleen de laatste mag cirkels neerzetten, anders
    // staan ze er dubbel.
    final volgnummer = ++_tekenVolgnummer;
    await c.setGeoJsonSource(_routeBron, {
      'type': 'FeatureCollection',
      'features': [
        for (final (i, route) in widget.routes.indexed)
          {
            'type': 'Feature',
            'id': i,
            'properties': {'gekozen': i == widget.gekozen, 'index': i},
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (final p in route.punten) [p.longitude, p.latitude],
              ],
            },
          },
      ],
    });
    final route = widget.routes.isEmpty
        ? null
        : widget.routes[widget.gekozen.clamp(0, widget.routes.length - 1)];
    final begin = widget.punten.first?.punt, eind = widget.punten.last?.punt;
    await c.setGeoJsonSource(_aansluitBron, {
      'type': 'FeatureCollection',
      'features': [
        if (route != null && route.punten.isNotEmpty)
          for (final (klik, weg) in [
            (begin, route.punten.first),
            (eind, route.punten.last),
          ])
            if (klik != null && meters(klik, weg) > _minAansluiting)
              {
                'type': 'Feature',
                'properties': <String, dynamic>{},
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    [klik.longitude, klik.latitude],
                    [weg.longitude, weg.latitude],
                  ],
                },
              },
      ],
    });
    await c.clearCircles();
    _cirkelIndex.clear();
    if (volgnummer != _tekenVolgnummer) return;
    final laatste = widget.punten.length - 1;
    for (final (i, plaats) in widget.punten.indexed) {
      if (plaats == null) continue;
      final cirkel = await c.addCircle(
        CircleOptions(
          geometry: plaats.punt,
          circleRadius: 9,
          circleColor: i == 0
              ? '#2e7d32'
              : (i == laatste ? '#c62828' : '#ef6c00'),
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2.5,
          draggable: true,
        ),
      );
      _cirkelIndex[cirkel.id] = i;
    }
    // In het zoekscherm; in het routescherm is dezelfde plaats al een routepunt.
    final gevonden = widget.gevonden;
    if (gevonden != null && !widget.punten.contains(gevonden)) {
      await c.addCircle(
        CircleOptions(
          geometry: gevonden.punt,
          circleRadius: 9,
          circleColor: '#1565c0',
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2.5,
        ),
      );
    }
    if (widget.beeldVersie != _ingepast) {
      _ingepast = widget.beeldVersie;
      await _brengInBeeld();
    }
  }

  void _versleept(
    Point<double> _,
    LatLng _,
    LatLng huidig,
    LatLng _,
    String id,
    Annotation? _,
    DragEventType soort,
  ) {
    // De plugin verschuift de cirkel zelf; pas bij het loslaten is er een nieuw
    // punt om een route voor te rekenen.
    final index = _cirkelIndex[id];
    if (soort == DragEventType.end && index != null) {
      widget.onPuntVersleept(index, huidig);
    }
  }

  Future<void> _brengInBeeld() async {
    final alle = [
      for (final route in widget.routes) ...route.punten,
      for (final plaats in widget.punten) ?plaats?.punt,
      if (widget.routes.isEmpty) ?widget.gevonden?.punt,
    ];
    if (alle.isEmpty) return;
    if (alle.length == 1) {
      await _controller!.animateCamera(
        CameraUpdate.newLatLngZoom(alle.first, 14),
      );
      return;
    }
    var zuid = 90.0, noord = -90.0, west = 180.0, oost = -180.0;
    for (final p in alle) {
      zuid = min(zuid, p.latitude);
      noord = max(noord, p.latitude);
      west = min(west, p.longitude);
      oost = max(oost, p.longitude);
    }
    await _controller!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(zuid, west),
          northeast: LatLng(noord, oost),
        ),
        left: widget.rand.left + 40,
        top: widget.rand.top + 40,
        // Rechts staan de knoppen (laag, kompas, instellingen).
        right: widget.rand.right + 72,
        bottom: widget.rand.bottom + 40,
      ),
    );
  }

  void _featureGetikt(
    Point<double> _,
    LatLng _,
    String id,
    String laag,
    Annotation? _,
  ) {
    if (!_lagen.contains(laag)) return;
    final index = int.tryParse(id);
    if (index != null && index < widget.routes.length) {
      widget.onRouteGekozen(index);
    }
  }

  @override
  Widget build(BuildContext context) => MapLibreMap(
    styleString: widget.stijlUrl,
    initialCameraPosition: widget.start,
    trackCameraPosition: true,
    // Het kompas van de plugin staat rechtsboven, precies onder onze eigen knoppen;
    // het scherm heeft er een eigen knop voor.
    compassEnabled: false,
    attributionButtonPosition: AttributionButtonPosition.bottomRight,
    onMapCreated: (controller) {
      _controller = controller;
      controller.onFeatureTapped.add(_featureGetikt);
      controller.onFeatureDrag.add(_versleept);
      widget.onController?.call(controller);
    },
    onStyleLoadedCallback: _stijlGeladen,
    onMapLongClick: widget.onLangIngedrukt,
  );
}
