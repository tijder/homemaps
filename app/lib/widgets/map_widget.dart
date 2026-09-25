import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/dawarich.dart';
import '../models/place.dart';
import '../models/route.dart';
import '../map/map_images.dart';
import '../map/route_geojson.dart';
import '../navigation/route_geometry.dart';
import '../navigation/turn_arrow.dart';
import '../providers/location.dart';
import '../utils/distance.dart';

/// The map with the routes and the points on it. Knows nothing about the
/// planner: gets what it has to draw and reports what is tapped.
class MapWidget extends StatefulWidget {
  const MapWidget({
    super.key,
    required this.styleUrl,
    required this.start,
    required this.points,
    required this.found,
    required this.viewVersion,
    required this.onPointDragged,
    required this.routes,
    required this.chosen,
    required this.onRouteChosen,
    required this.onLongPress,
    required this.padding,
    this.location,
    this.follow,
    this.driven,
    this.arrow,
    this.navigating = false,
    this.onUserMoved,
    this.traffic,
    this.showDelay = true,
    this.onTrafficTapped,
    this.enforcement,
    this.family = const [],
    this.onFamilyTapped,
    this.onController,
  });

  /// The URL of the map style, or the style itself as JSON (the night version).
  final String styleUrl;
  final CameraPosition start;

  /// The points of the route (from, vias, to); draggable on the map.
  final List<Place?> points;

  /// The place from the search screen: a fixed, blue dot.
  final Place? found;

  /// Goes up when the result has to be brought into view (see PlannerState).
  final int viewVersion;
  final void Function(int index, LatLng point) onPointDragged;
  final List<RouteOption> routes;
  final int chosen;
  final ValueChanged<int> onRouteChosen;
  final void Function(Point<double> screen, LatLng point) onLongPress;

  /// The space the panel covers on the map; the route is brought into view
  /// outside of it.
  final EdgeInsets padding;

  /// Your own location (the blue dot), or null if the location is off.
  final LocationFix? location;

  /// During navigation: the camera follows, tilted and in the direction of
  /// travel, with your location in the lower part of the view. Null = the map
  /// is free.
  final ({LatLng point, double heading, double speed})? follow;

  /// During navigation: the part of the route already behind you, grey over
  /// the blue line.
  final List<LatLng>? driven;

  /// The bit of route around the next turn, as an arrow on the map (see
  /// [turnArrow]); null without an arrow.
  final List<LatLng>? arrow;

  /// During navigation the center of the map is lower (see [follow]), also
  /// while you look around yourself; afterwards the map goes flat and
  /// north-up again.
  final bool navigating;

  /// The user touches the map themselves (pan, pinch, scroll): then following
  /// has to pause.
  final VoidCallback? onUserMoved;

  /// The traffic layer (GeoJSON from `/traffic`), or null if it is off.
  final Map<String, dynamic>? traffic;

  /// Show jams and slow traffic; closures and roadworks are always shown.
  final bool showDelay;

  /// A tap on a piece of traffic, with the properties from the GeoJSON.
  final void Function(Point<double> screen, Map<String, dynamic> properties)?
  onTrafficTapped;

  /// Speed cameras, sections and red light cameras (GeoJSON from
  /// `/enforcement`), or null if they are off. A tap on one goes to
  /// [onTrafficTapped] too.
  final Map<String, dynamic>? enforcement;

  /// The family members who share their location via Dawarich.
  final List<FamilyLocation> family;
  final ValueChanged<FamilyLocation>? onFamilyTapped;
  final ValueChanged<MapLibreMapController>? onController;

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  static const _routeSource = 'routes';
  static const _connectorSource = 'connector';
  static const _trafficSource = 'traffic';
  static const _enforcementSource = 'enforcement';
  static const _drivenSource = 'driven';
  static const _arrowSource = 'arrow';
  static const _familySource = 'family';

  /// After this long without a new location a family member turns grey.
  static const _familyStale = Duration(hours: 1);

  /// Below this the gap between a point and the road isn't worth showing.
  static const _minConnector = 15.0;
  static const _layers = ['route-alt', 'route-casing', 'route'];

  MapLibreMapController? _controller;
  bool _styleReady = false;

  /// Feature id -> properties, to show what is there on a tap.
  var _trafficInfo = <String, Map<String, dynamic>>{};
  var _enforcementInfo = <String, Map<String, dynamic>>{};

  /// Circle id -> index in [MapWidget.points]; the found place isn't in it.
  final _circleIndex = <String, int>{};

  /// The family markers the style already has (per letter and color).
  final _familyImages = <String>{};
  int _fittedVersion = 0;
  int _drawSequence = 0;

  @override
  void didUpdateWidget(MapWidget old) {
    super.didUpdateWidget(old);
    if (old.styleUrl != widget.styleUrl) {
      // A new style throws away all sources and layers; onStyleLoaded puts
      // them back.
      _styleReady = false;
      return;
    }
    if (!_styleReady) return;
    if (old.location != widget.location) _showLocation();
    if (old.driven != widget.driven) _drawDriven();
    if (old.arrow != widget.arrow) _drawArrow();
    if (old.family != widget.family) _drawFamily();
    if (old.navigating != widget.navigating) _setPadding();
    if (widget.follow != null && old.follow != widget.follow) _follow();
    if (old.traffic != widget.traffic || old.showDelay != widget.showDelay) {
      _drawTraffic();
    }
    if (old.enforcement != widget.enforcement) _drawEnforcement();
    if (old.routes != widget.routes ||
        old.chosen != widget.chosen ||
        // The screen rebuilds this list every time; compare by content,
        // otherwise the circles are replaced on every rebuild.
        !listEquals(old.points, widget.points) ||
        old.found != widget.found ||
        old.viewVersion != widget.viewVersion) {
      _draw();
    }
  }

  Future<void> _styleLoaded() async {
    final c = _controller!;
    // The circles of the points are annotations; their layer already exists. The
    // route lines have to go below it, otherwise a point hides behind its own
    // route.
    final below = c.circleManager?.layerIds.firstOrNull;
    await c.addGeoJsonSource(_trafficSource, _empty);
    await c.addGeoJsonSource(_routeSource, _empty);
    await c.addGeoJsonSource(_connectorSource, _empty);
    await _trafficLayers(c, belowText: await _firstTextLayer(c));
    await _enforcementLayer(c);
    // Alternatives grey and at the bottom; the chosen route blue with a white
    // casing.
    await c.addLineLayer(
      _routeSource,
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
        ['get', 'chosen'],
        false,
      ],
    );
    await c.addLineLayer(
      _routeSource,
      'route-casing',
      const LineLayerProperties(
        lineColor: '#ffffff',
        lineWidth: 9,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'chosen'],
        true,
      ],
      enableInteraction: false,
    );
    await c.addLineLayer(
      _routeSource,
      'route',
      const LineLayerProperties(
        lineColor: '#1565c0',
        lineWidth: 6,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'chosen'],
        true,
      ],
    );
    await c.addGeoJsonSource(_drivenSource, _empty);
    await c.addLineLayer(
      _drivenSource,
      'driven',
      const LineLayerProperties(
        lineColor: '#9e9e9e',
        lineWidth: 6,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    // The arrow at the next turn: white with a dark casing over the route,
    // with a head at the end, as in Google and Apple Maps.
    await c.addGeoJsonSource(_arrowSource, _empty);
    await c.addLineLayer(
      _arrowSource,
      'arrow-casing',
      const LineLayerProperties(
        lineColor: '#0d47a1',
        lineWidth: 11,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: ['==', '\$type', 'LineString'],
      enableInteraction: false,
    );
    await c.addLineLayer(
      _arrowSource,
      'arrow',
      const LineLayerProperties(
        lineColor: '#ffffff',
        lineWidth: 6,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: ['==', '\$type', 'LineString'],
      enableInteraction: false,
    );
    try {
      await c.addImage(_arrowHeadImage, await arrowHeadPng());
      await c.addSymbolLayer(
        _arrowSource,
        'arrow-head',
        const SymbolLayerProperties(
          iconImage: _arrowHeadImage,
          iconSize: 0.5,
          iconAnchor: 'bottom',
          iconRotate: [Expressions.get, 'bearing'],
          iconRotationAlignment: 'map',
          iconPitchAlignment: 'map',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
        filter: ['==', '\$type', 'Point'],
        enableInteraction: false,
      );
    } catch (_) {
      // Without a head the line is still the arrow.
    }
    // From where you clicked to where the route picks up the road: Valhalla
    // snaps a point next to the road to the nearest road, and without this
    // little line the route then seems to start somewhere else.
    await c.addLineLayer(
      _connectorSource,
      'connector',
      const LineLayerProperties(
        lineColor: '#546e7a',
        lineWidth: 3,
        lineDasharray: [0.5, 2],
        lineCap: 'round',
      ),
      enableInteraction: false,
      belowLayerId: below,
    );
    // The family on top: a circle with a letter, as on the website.
    await c.addGeoJsonSource(_familySource, _empty);
    await c.addSymbolLayer(
      _familySource,
      'family',
      const SymbolLayerProperties(
        iconImage: [Expressions.get, 'image'],
        iconSize: 0.5,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
    );
    _familyImages.clear();
    _styleReady = true;
    _circleIndex.clear();
    _fittedVersion = 0;
    await _drawTraffic();
    await _drawEnforcement();
    await _drawDriven();
    await _drawArrow();
    await _drawFamily();
    await _showLocation();
    await _draw();
  }

  Future<void> _drawDriven() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    await c.setGeoJsonSource(
      _drivenSource,
      lineFeatureCollection(widget.driven),
    );
  }

  static const _arrowHeadImage = 'arrow-head';

  Future<void> _drawArrow() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    await c.setGeoJsonSource(
      _arrowSource,
      arrowFeatureCollection(widget.arrow),
    );
  }

  /// A family member: a colored circle with a white border and the first
  /// letter of the email address.
  static Future<Uint8List> _familyMarker(String letter, bool old) async {
    const size = 72.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(size / 2, size / 2);
    canvas
      ..drawCircle(center, size / 2 - 2, Paint()..color = Colors.white)
      ..drawCircle(
        center,
        size / 2 - 8,
        Paint()
          ..color = old ? const Color(0xFF9E9E9E) : const Color(0xFF6A1B9A),
      );
    final text = TextPainter(
      text: TextSpan(
        text: letter,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  }

  Future<void> _drawFamily() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    final now = DateTime.now();
    final features = <Map<String, dynamic>>[];
    for (final member in widget.family) {
      final old = now.difference(member.time) > _familyStale;
      final image = 'family-${member.initial}-${old ? 'stale' : 'fresh'}';
      if (_familyImages.add(image)) {
        try {
          await c.addImage(image, await _familyMarker(member.initial, old));
        } catch (_) {
          _familyImages.remove(image);
          continue;
        }
      }
      features.add({
        'type': 'Feature',
        'id': '${member.userId}',
        'properties': {'image': image},
        'geometry': {
          'type': 'Point',
          'coordinates': [member.point.longitude, member.point.latitude],
        },
      });
    }
    // Another style may have thrown everything away in the meantime.
    if (!_styleReady) return;
    await c.setGeoJsonSource(_familySource, {
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  /// Following: your location at about two thirds of the height, so you see
  /// what lies ahead of you.
  Future<void> _setPadding() async {
    final c = _controller;
    if (c == null) return;
    final elevation = MediaQuery.sizeOf(context).height;
    await c.updateContentInsets(
      widget.navigating
          ? EdgeInsets.only(top: elevation * 0.35)
          : EdgeInsets.zero,
      // Not animated: the next easeCamera would cut that animation short right
      // away, and then the padding stays stuck at zero.
      false,
    );
    if (!widget.navigating) {
      final now = c.cameraPosition;
      if (now != null) {
        await c.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: now.target, zoom: now.zoom),
          ),
        );
      }
    }
  }

  Future<void> _follow() async {
    final follow = widget.follow, c = _controller;
    if (follow == null || c == null) return;
    // Slow: close by; on the motorway look further ahead.
    final zoom = followZoom(follow.speed);
    await c.easeCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: follow.point,
          zoom: zoom,
          bearing: follow.heading,
          tilt: followTilt,
        ),
      ),
      // About the time until the next fix, and linear: that way the map glides
      // without accelerating and braking on every fix.
      duration: const Duration(milliseconds: 1000),
      interpolation: CameraAnimationInterpolation.linear,
    );
  }

  /// The dot comes from our own source (ManualLocationSource), not from the
  /// plugin: that way it is the same on the web and on Android, and the
  /// navigation can later use the same fixes for it.
  Future<void> _showLocation() async {
    final c = _controller, fix = widget.location;
    if (c == null || fix == null) return;
    await c.updateManualLocation(
      ManualLocationUpdate(
        target: fix.point,
        horizontalAccuracy: fix.accuracy,
        bearing: fix.heading,
        speed: fix.speed,
        timestamp: fix.time,
      ),
    );
  }

  /// Below the routes, so a route over a jam stays readable, and the lines
  /// also below the map's names and road numbers ([belowText]). The incidents
  /// (points) stay above them. A closure is red with white dashes, roadworks
  /// orange striped, jams red and slow traffic orange. Only from a zoom at
  /// which you can tell roads apart: nationwide there are hundreds.
  Future<void> _trafficLayers(
    MapLibreMapController c, {
    String? belowText,
  }) async {
    List<Object> width(double low, double high) => [
      'interpolate',
      ['linear'],
      ['zoom'],
      8,
      low,
      15,
      high,
    ];
    List<Object> kind(List<String> kinds) => [
      'in',
      ['get', 'kind'],
      ['literal', kinds],
    ];
    await c.addLineLayer(
      _trafficSource,
      'traffic-slow',
      LineLayerProperties(
        lineColor: [
          'match',
          ['get', 'kind'],
          'jam',
          '#c62828',
          '#ef6c00',
        ],
        lineWidth: width(2.5, 7),
        // Nationwide only the jams; slow traffic is added from zoom 9.
        lineOpacity: [
          'interpolate',
          ['linear'],
          ['zoom'],
          8,
          [
            'match',
            ['get', 'kind'],
            'jam',
            0.85,
            0,
          ],
          9.5,
          0.85,
        ],
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: kind(['slow', 'jam']),
      minzoom: 7,
      belowLayerId: belowText,
    );
    await c.addLineLayer(
      _trafficSource,
      'traffic-roadworks',
      LineLayerProperties(
        lineColor: '#f9a825',
        lineWidth: width(2.5, 7),
        lineDasharray: const [1.5, 1],
      ),
      filter: kind(['roadworks']),
      minzoom: 9,
      belowLayerId: belowText,
    );
    await c.addLineLayer(
      _trafficSource,
      'traffic-closed',
      LineLayerProperties(
        lineColor: '#d32f2f',
        lineWidth: width(3, 8),
        lineCap: 'round',
      ),
      filter: kind(['closed']),
      minzoom: 9,
      belowLayerId: belowText,
    );
    await c.addLineLayer(
      _trafficSource,
      'traffic-closed-stripes',
      LineLayerProperties(
        lineColor: '#ffffff',
        lineWidth: width(1, 3),
        lineDasharray: const [1, 1.5],
      ),
      filter: kind(['closed']),
      minzoom: 9,
      enableInteraction: false,
      belowLayerId: belowText,
    );
    // You can't hit a line of a few pixels with a finger: a wide, nearly
    // invisible line over it catches the tap. A fraction visible instead of 0,
    // so MapLibre surely counts it on a tap.
    await c.addLineLayer(
      _trafficSource,
      'traffic-hit',
      const LineLayerProperties(
        lineColor: '#000000',
        lineWidth: 20,
        lineOpacity: 0.01,
      ),
      minzoom: 9,
      belowLayerId: belowText,
    );
    // Accidents, breakdowns and objects on the road: points, on top of the
    // lines. With a wide, nearly invisible circle around them for the tap.
    // Only up close: across the country there are easily a hundred, and en
    // route the navigation warns about what is on your route anyway.
    await c.addCircleLayer(
      _trafficSource,
      'traffic-incident',
      const CircleLayerProperties(
        circleRadius: [
          'interpolate',
          ['linear'],
          ['zoom'],
          8,
          4,
          14,
          8,
        ],
        circleColor: [
          'match',
          ['get', 'kind'],
          'accident',
          '#c62828',
          'breakdown',
          '#ef6c00',
          '#f9a825',
        ],
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ),
      filter: kind(['accident', 'breakdown', 'obstacle']),
      minzoom: _incidentMinZoom,
    );
    await c.addCircleLayer(
      _trafficSource,
      'traffic-incident-hit',
      const CircleLayerProperties(
        circleRadius: 18,
        circleColor: '#000000',
        circleOpacity: 0.01,
      ),
      filter: kind(['accident', 'breakdown', 'obstacle']),
      minzoom: _incidentMinZoom,
    );
  }

  static const _incidentMinZoom = 11.0;

  /// The image per kind in the enforcement layer.
  static const _cameraImages = {
    'speed_camera': ('camera-speed', Icons.photo_camera),
    'red_light': ('camera-red-light', Icons.traffic),
    'section_start': ('camera-section', Icons.timer_outlined),
    'section_end': ('camera-section-end', Icons.timer_off_outlined),
  };

  /// Speed cameras as small signs, above the traffic, from the same zoom as
  /// the incidents: nationwide there are hundreds.
  Future<void> _enforcementLayer(MapLibreMapController c) async {
    await c.addGeoJsonSource(_enforcementSource, _empty);
    try {
      for (final (image, icon) in _cameraImages.values) {
        await c.addImage(image, await cameraPng(icon));
      }
      await c.addSymbolLayer(
        _enforcementSource,
        'enforcement',
        SymbolLayerProperties(
          iconImage: [
            'match',
            ['get', 'kind'],
            for (final MapEntry(key: kind, value: (image, _))
                in _cameraImages.entries) ...[kind, image],
            _cameraImages['speed_camera']!.$1,
          ],
          iconSize: const [
            'interpolate',
            ['linear'],
            ['zoom'],
            _incidentMinZoom,
            0.35,
            16,
            0.55,
          ],
          iconAllowOverlap: true,
        ),
        minzoom: _incidentMinZoom,
      );
    } catch (_) {
      // Without images there are no signs; the rest of the map is fine.
    }
  }

  Future<void> _drawEnforcement() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    final features = [
      for (final feature
          in (widget.enforcement?['features'] as List? ?? const []))
        if (feature is Map<String, dynamic>) feature,
    ];
    _enforcementInfo = {
      for (final feature in features)
        '${feature['id']}': (feature['properties'] as Map)
            .cast<String, dynamic>(),
    };
    await c.setGeoJsonSource(_enforcementSource, {
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  /// The style's first layer with text or symbols: what goes below it doesn't
  /// run over names and road numbers. Null if there is none or if it fails;
  /// then it goes on top. Not via getStyle(): that doesn't work on the web
  /// under wasm (the plugin fetches the style differently there).
  Future<String?> _firstTextLayer(MapLibreMapController c) async {
    try {
      for (final id in await c.getLayerIds()) {
        if (id is! String) continue;
        final layer = await c.getLayerProperties(id);
        if (layer?['type'] == 'symbol') return id;
      }
    } on Exception {
      return null;
    }
    return null;
  }

  static const _onMapWithoutDelay = {
    'closed',
    'roadworks',
    'accident',
    'breakdown',
    'obstacle',
  };
  static const _onMap = {..._onMapWithoutDelay, 'slow', 'jam'};

  Future<void> _drawTraffic() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    final features = [
      for (final feature in (widget.traffic?['features'] as List? ?? const []))
        if (feature is Map<String, dynamic> &&
            // Only what belongs on the map; temporary speed limits, MSI signs
            // and open bridges are for en route.
            (widget.showDelay ? _onMap : _onMapWithoutDelay).contains(
              (feature['properties'] as Map?)?['kind'],
            ))
          feature,
    ];
    _trafficInfo = {
      for (final feature in features)
        '${feature['id']}': (feature['properties'] as Map)
            .cast<String, dynamic>(),
    };
    await c.setGeoJsonSource(_trafficSource, {
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  static const _empty = emptyFeatureCollection;

  Future<void> _draw() async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    // Two updates shortly after each other: only the last may place circles,
    // otherwise they show up twice.
    final sequence = ++_drawSequence;
    await c.setGeoJsonSource(
      _routeSource,
      routesFeatureCollection(widget.routes, widget.chosen),
    );
    final route = widget.routes.isEmpty
        ? null
        : widget.routes[widget.chosen.clamp(0, widget.routes.length - 1)];
    final begin = widget.points.first?.point, end = widget.points.last?.point;
    await c.setGeoJsonSource(_connectorSource, {
      'type': 'FeatureCollection',
      'features': [
        if (route != null && route.points.isNotEmpty)
          for (final (click, road) in [
            (begin, route.points.first),
            (end, route.points.last),
          ])
            if (click != null && meters(click, road) > _minConnector)
              {
                'type': 'Feature',
                'properties': <String, dynamic>{},
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    [click.longitude, click.latitude],
                    [road.longitude, road.latitude],
                  ],
                },
              },
      ],
    });
    await c.clearCircles();
    _circleIndex.clear();
    if (sequence != _drawSequence) return;
    final latest = widget.points.length - 1;
    for (final (i, place) in widget.points.indexed) {
      if (place == null) continue;
      final circle = await c.addCircle(
        CircleOptions(
          geometry: place.point,
          circleRadius: 9,
          circleColor: i == 0
              ? '#2e7d32'
              : (i == latest ? '#c62828' : '#ef6c00'),
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2.5,
          draggable: true,
        ),
      );
      _circleIndex[circle.id] = i;
    }
    // In the search screen; in the route screen the same place is already a
    // route point.
    final found = widget.found;
    if (found != null && !widget.points.contains(found)) {
      await c.addCircle(
        CircleOptions(
          geometry: found.point,
          circleRadius: 9,
          circleColor: '#1565c0',
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2.5,
        ),
      );
    }
    if (widget.viewVersion != _fittedVersion) {
      _fittedVersion = widget.viewVersion;
      await _fitToView();
    }
  }

  void _dragged(
    Point<double> _,
    LatLng _,
    LatLng current,
    LatLng _,
    String id,
    Annotation? _,
    DragEventType kind,
  ) {
    // The plugin moves the circle itself; only on release is there a new point
    // to calculate a route for.
    final index = _circleIndex[id];
    if (kind == DragEventType.end && index != null) {
      widget.onPointDragged(index, current);
    }
  }

  Future<void> _fitToView() async {
    final all = [
      for (final route in widget.routes) ...route.points,
      for (final place in widget.points) ?place?.point,
      if (widget.routes.isEmpty) ?widget.found?.point,
    ];
    if (all.isEmpty) return;
    if (all.length == 1) {
      await _controller!.animateCamera(
        CameraUpdate.newLatLngZoom(all.first, 14),
      );
      return;
    }
    var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
    for (final p in all) {
      south = min(south, p.latitude);
      north = max(north, p.latitude);
      west = min(west, p.longitude);
      east = max(east, p.longitude);
    }
    await _controller!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        left: widget.padding.left + 40,
        top: widget.padding.top + 40,
        // The buttons are on the right (layer, compass, settings).
        right: widget.padding.right + 72,
        bottom: widget.padding.bottom + 40,
      ),
    );
  }

  void _featureTapped(
    Point<double> screen,
    LatLng _,
    String id,
    String layer,
    Annotation? _,
  ) {
    if (layer == 'family') {
      final member = widget.family
          .where((f) => '${f.userId}' == id)
          .firstOrNull;
      if (member != null) widget.onFamilyTapped?.call(member);
      return;
    }
    if (layer == 'enforcement') {
      final info = _enforcementInfo[id];
      if (info != null) widget.onTrafficTapped?.call(_logical(screen), info);
      return;
    }
    if (layer.startsWith('traffic-')) {
      final info = _trafficInfo[id];
      if (info != null) widget.onTrafficTapped?.call(_logical(screen), info);
      return;
    }
    if (!_layers.contains(layer)) return;
    final index = int.tryParse(id);
    if (index != null && index < widget.routes.length) {
      widget.onRouteChosen(index);
    }
  }

  /// The plugin gives screen points in physical pixels on Android
  /// (Projection.toScreenLocation), in CSS pixels on the web. Flutter works in
  /// logical pixels: without this conversion the point menu ended up far out
  /// of view on a screen with density 3, pushed to the bottom right.
  Point<double> _logical(Point<double> screen) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return screen;
    }
    final density = MediaQuery.devicePixelRatioOf(context);
    return Point(screen.x / density, screen.y / density);
  }

  @override
  Widget build(BuildContext context) => Listener(
    // On Android touches on the map pass through here; on the web they go to
    // the map's HTML element, where mouse_web.dart catches them.
    onPointerDown: (_) => widget.onUserMoved?.call(),
    child: _map(),
  );

  Widget _map() => MapLibreMap(
    styleString: widget.styleUrl,
    initialCameraPosition: widget.start,
    trackCameraPosition: true,
    // The plugin's compass is at the top right, right below our own buttons;
    // the screen has its own button for it.
    compassEnabled: false,
    myLocationEnabled: widget.location != null,
    locationSource: const ManualLocationSource(),
    attributionButtonPosition: AttributionButtonPosition.bottomRight,
    onMapCreated: (controller) {
      _controller = controller;
      controller.onFeatureTapped.add(_featureTapped);
      controller.onFeatureDrag.add(_dragged);
      widget.onController?.call(controller);
    },
    onStyleLoadedCallback: _styleLoaded,
    onMapLongClick: (screen, point) =>
        widget.onLongPress(_logical(screen), point),
  );
}
