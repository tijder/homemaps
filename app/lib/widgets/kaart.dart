import 'dart:math';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/plaats.dart';
import '../models/route.dart';

/// De kaart met de routes en de punten erop. Weet niets van de planner: krijgt
/// wat hij moet tekenen en meldt wat er wordt aangetikt.
class Kaart extends StatefulWidget {
  const Kaart({
    super.key,
    required this.stijlUrl,
    required this.start,
    required this.punten,
    required this.routes,
    required this.gekozen,
    required this.onRouteGekozen,
    required this.onLangIngedrukt,
    required this.rand,
    this.onController,
  });

  final String stijlUrl;
  final CameraPosition start;
  final List<Plaats?> punten;
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
  static const _routeBron = 'routes', _puntBron = 'punten';
  static const _lagen = ['route-alt', 'route-rand', 'route', 'punt'];

  MapLibreMapController? _controller;
  bool _stijlKlaar = false;

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
        oud.punten != widget.punten) {
      _teken(pasBeeldAan: oud.routes != widget.routes);
    }
  }

  Future<void> _stijlGeladen() async {
    final c = _controller!;
    await c.addGeoJsonSource(_routeBron, _leeg);
    await c.addGeoJsonSource(_puntBron, _leeg);
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
    await c.addCircleLayer(
      _puntBron,
      'punt',
      const CircleLayerProperties(
        circleRadius: 8,
        circleColor: [
          'match',
          ['get', 'rol'],
          'van',
          '#2e7d32',
          'naar',
          '#c62828',
          '#ef6c00',
        ],
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2.5,
      ),
      enableInteraction: false,
    );
    _stijlKlaar = true;
    await _teken(pasBeeldAan: widget.routes.isNotEmpty);
  }

  static const _leeg = {'type': 'FeatureCollection', 'features': <dynamic>[]};

  Future<void> _teken({required bool pasBeeldAan}) async {
    final c = _controller;
    if (c == null || !_stijlKlaar) return;
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
    final laatste = widget.punten.length - 1;
    await c.setGeoJsonSource(_puntBron, {
      'type': 'FeatureCollection',
      'features': [
        for (final (i, plaats) in widget.punten.indexed)
          if (plaats != null)
            {
              'type': 'Feature',
              'properties': {
                'rol': i == 0 ? 'van' : (i == laatste ? 'naar' : 'via'),
              },
              'geometry': {
                'type': 'Point',
                'coordinates': [plaats.punt.longitude, plaats.punt.latitude],
              },
            },
      ],
    });
    if (pasBeeldAan) await _brengInBeeld();
  }

  Future<void> _brengInBeeld() async {
    final alle = [
      for (final route in widget.routes) ...route.punten,
      for (final plaats in widget.punten) ?plaats?.punt,
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
        right: widget.rand.right + 40,
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
    compassEnabled: true,
    attributionButtonPosition: AttributionButtonPosition.bottomRight,
    onMapCreated: (controller) {
      _controller = controller;
      controller.onFeatureTapped.add(_featureGetikt);
      widget.onController?.call(controller);
    },
    onStyleLoadedCallback: _stijlGeladen,
    onMapLongClick: widget.onLangIngedrukt,
  );
}
