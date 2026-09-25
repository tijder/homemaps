import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'car/car_bridge.dart';
import 'l10n/app_localizations.dart';
import 'navigation/simulation.dart';
import 'providers/services.dart';
import 'providers/settings.dart';
import 'providers/location.dart';
import 'providers/location_sharing.dart';
import 'router/app_router.dart';
import 'services/app_log.dart';

Future<void> main() async {
  final container = await bootstrap();
  runApp(
    UncontrolledProviderScope(container: container, child: const HomeMapsApp()),
  );
}

/// Everything before the first frame: the settings, the web config and the
/// providers that have to be there from the start. Also without a screen: in
/// the car the engine may start before the phone's window exists.
Future<ProviderContainer> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  // First, so problems while starting end up in the log too.
  unawaited(AppLog.instance.install());
  var webConfig = const <String, dynamic>{};
  if (kIsWeb) {
    // maplibre-gl-js lives in web/maplibre/ and not on a CDN: otherwise every
    // map view would call out. It has to be a full URL -- import() reads a
    // relative one as a bare module name.
    MapLibreMap.webLibrarySource = MapLibreJsSource.urls(
      scriptUrl: Uri.base.resolve('maplibre/maplibre-gl.mjs').toString(),
      styleUrl: Uri.base.resolve('maplibre/maplibre-gl.css').toString(),
    );
    webConfig = await _loadWebConfig();
    // The right mouse button belongs to the app here (the point menu on the
    // map); the browser's menu would appear on top of it.
    await BrowserContextMenu.disableContextMenu();
  }
  final box = await openSettings();
  final queue = await openShareQueue();
  // Test navigation without driving: ?simulate=lat,lon (see SimulationSource).
  final simulation = kIsWeb ? SimulationSource.fromUrl(Uri.base) : null;
  final container = ProviderContainer(
    overrides: [
      settingsBoxProvider.overrideWithValue(box),
      shareQueueBoxProvider.overrideWithValue(queue),
      webConfigProvider.overrideWithValue(webConfig),
      if (simulation != null)
        locationSourceProvider.overrideWithBuild((_, _) => simulation),
    ],
  );
  // Location sharing listens to navigation itself; it has to be there from the
  // start, also to send a queue left over from last time.
  container.read(locationSharerProvider);
  // The car (Android Auto, CarPlay) talks to Dart from the start too.
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    container.read(carBridgeProvider);
  }
  return container;
}

/// `/config.json` is optional: the chart mounts it, a bare web server doesn't.
Future<Map<String, dynamic>> _loadWebConfig() async {
  try {
    final response = await Dio().getUri<Map<String, dynamic>>(
      Uri.base.resolve('config.json'),
      options: Options(receiveTimeout: const Duration(seconds: 5)),
    );
    return response.data ?? const {};
  } on Object {
    return const {};
  }
}

class HomeMapsApp extends StatefulWidget {
  const HomeMapsApp({super.key});

  @override
  State<HomeMapsApp> createState() => _HomeMapsAppState();
}

class _HomeMapsAppState extends State<HomeMapsApp> {
  final _router = AppRouter();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    routerConfig: _router.config(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1565C0),
        brightness: Brightness.dark,
      ),
    ),
  );
}
