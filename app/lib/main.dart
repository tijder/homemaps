import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'l10n/app_localizations.dart';
import 'providers/diensten.dart';
import 'providers/instellingen.dart';
import 'router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var webConfig = const <String, dynamic>{};
  if (kIsWeb) {
    // maplibre-gl-js staat in web/maplibre/ en niet op een CDN: anders gaat elke
    // kaartweergave naar buiten. Het moet een volledige URL zijn -- een relatieve
    // leest import() als kale modulenaam.
    MapLibreMap.webLibrarySource = MapLibreJsSource.urls(
      scriptUrl: Uri.base.resolve('maplibre/maplibre-gl.mjs').toString(),
      styleUrl: Uri.base.resolve('maplibre/maplibre-gl.css').toString(),
    );
    webConfig = await _laadWebConfig();
    // De rechtermuisknop is hier van de app (het puntmenu op de kaart); het menu
    // van de browser zou eroverheen komen.
    await BrowserContextMenu.disableContextMenu();
  }
  final doos = await openInstellingen();
  runApp(
    ProviderScope(
      overrides: [
        instellingenDoosProvider.overrideWithValue(doos),
        webConfigProvider.overrideWithValue(webConfig),
      ],
      child: const HomeMapsApp(),
    ),
  );
}

/// `/config.json` is optioneel: de chart mount hem, een kale webserver niet.
Future<Map<String, dynamic>> _laadWebConfig() async {
  try {
    final antwoord = await Dio().getUri<Map<String, dynamic>>(
      Uri.base.resolve('config.json'),
      options: Options(receiveTimeout: const Duration(seconds: 5)),
    );
    return antwoord.data ?? const {};
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
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitel,
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
