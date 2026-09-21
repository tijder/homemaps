import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

// Fase 0-spike: bewijst dat maplibre_gl met een zelfgehoste maplibre-gl-js, de
// stijl van de eigen tileserver, een GeoJSON-lijn en een marker werkt -- op
// Android en als wasm-build voor web.
const _styleUrl =
    'https://tiles.maps.droogers.cloud/styles/osm-bright/style.json';

void main() {
  if (kIsWeb) {
    // Opgelost tegen de pagina, zodat het onder elke base-href werkt. Het moet een
    // volledige URL zijn: een dynamische `import()` leest 'maplibre/…' als een kale
    // modulenaam en weigert die ("Failed to resolve module specifier").
    MapLibreMap.webLibrarySource = MapLibreJsSource.urls(
      scriptUrl: Uri.base.resolve('maplibre/maplibre-gl.mjs').toString(),
      styleUrl: Uri.base.resolve('maplibre/maplibre-gl.css').toString(),
    );
  }
  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(title: 'HomeMaps', home: SpikePage());
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  MapLibreMapController? _controller;

  static const _utrecht = LatLng(52.0907, 5.1214);
  static const _amsterdam = LatLng(52.3731, 4.8922);

  Future<void> _onStyleLoaded() async {
    final c = _controller!;
    await c.addGeoJsonSource('route', {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': <String, dynamic>{},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [_utrecht.longitude, _utrecht.latitude],
              [5.0, 52.2],
              [_amsterdam.longitude, _amsterdam.latitude],
            ],
          },
        },
      ],
    });
    await c.addLineLayer(
      'route',
      'route-lijn',
      const LineLayerProperties(
        lineColor: '#1565c0',
        lineWidth: 5,
        lineCap: 'round',
        lineJoin: 'round',
      ),
    );
    await c.addCircle(
      const CircleOptions(
        geometry: _amsterdam,
        circleRadius: 8,
        circleColor: '#c62828',
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ),
    );
    await c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            min(_utrecht.latitude, _amsterdam.latitude),
            min(_utrecht.longitude, _amsterdam.longitude),
          ),
          northeast: LatLng(
            max(_utrecht.latitude, _amsterdam.latitude),
            max(_utrecht.longitude, _amsterdam.longitude),
          ),
        ),
        left: 40,
        top: 40,
        right: 40,
        bottom: 40,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: MapLibreMap(
      styleString: _styleUrl,
      initialCameraPosition: const CameraPosition(target: _utrecht, zoom: 7),
      onMapCreated: (c) => _controller = c,
      onStyleLoadedCallback: _onStyleLoaded,
    ),
  );
}
