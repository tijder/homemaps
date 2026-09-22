import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/app_config.dart';
import '../services/langs_route.dart';
import '../services/photon_service.dart';
import '../services/valhalla_service.dart';
import '../utils/snelheid_tijden.dart';
import 'instellingen.dart';

final dioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
    ),
  ),
);

/// De inhoud van `/config.json`, alleen op het web. In main() geladen en hier
/// overschreven; een ontbrekend of leeg bestand is gewoon `{}`.
final webConfigProvider = Provider<Map<String, dynamic>>((ref) => const {});

/// Null zolang er op Android nog geen server is ingesteld.
final appConfigProvider = Provider<AppConfig?>((ref) {
  if (kIsWeb) {
    // De app wordt door dezelfde nginx geserveerd die de backends proxyt.
    final basis = Uri.base.resolve('.').toString();
    return AppConfig.vanServer(basis, ref.watch(webConfigProvider));
  }
  final server = ref.watch(instellingenProvider.select((i) => i.server));
  return server.isEmpty ? null : AppConfig.vanServer(server);
});

final photonProvider = Provider<PhotonService?>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config == null) return null;
  return PhotonService(ref.watch(dioProvider), config.geocodeUrl);
});

final valhallaProvider = Provider<ValhallaService?>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config == null) return null;
  return ValhallaService(ref.watch(dioProvider), config.valhallaUrl);
});

final langsRouteProvider = Provider<LangsRouteService?>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config == null) return null;
  return LangsRouteService(
    ref.watch(dioProvider),
    config.tilesUrl,
    config.valhallaUrl,
  );
});

/// Waar de kaart opent: het `center` uit de TileJSON van de eigen tileserver, zodat
/// een installatie voor een ander gebied niet op Nederland begint. Lukt dat niet,
/// dan is Nederland de terugval.
final kaartStartProvider = FutureProvider<CameraPosition>((ref) async {
  const terugval = CameraPosition(target: LatLng(52.2, 5.3), zoom: 6.5);
  final config = ref.watch(appConfigProvider);
  if (config == null) return terugval;
  try {
    final antwoord = await ref
        .watch(dioProvider)
        .get<Map<String, dynamic>>(
          '${config.tilesUrl}/data/v3.json',
          options: Options(receiveTimeout: const Duration(seconds: 5)),
        );
    final midden = (antwoord.data?['center'] as List?)?.cast<num>();
    if (midden == null || midden.length < 2) return terugval;
    return CameraPosition(
      target: LatLng(midden[1].toDouble(), midden[0].toDouble()),
      zoom: midden.length > 2 ? midden[2].toDouble() : 7,
    );
  } on Object {
    return terugval;
  }
});

/// Hoe vaak de verkeerslaag wordt ververst; de importer maakt hem elke vijf
/// minuten opnieuw.
const verkeerInterval = Duration(minutes: 5);

/// Onderweg vaker: de matrixborden boven de snelweg ververst de importer elke
/// minuut.
const verkeerIntervalOnderweg = Duration(minutes: 1);

/// Of er genavigeerd wordt; de navigatie zet hem. Dan ververst de verkeerslaag
/// vaker.
final onderwegProvider = NotifierProvider<OnderwegNotifier, bool>(
  OnderwegNotifier.new,
);

class OnderwegNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void zet(bool onderweg) => state = onderweg;
}

/// De verkeerslaag als GeoJSON, zolang iemand hem gebruikt: de kaart (als hij
/// daar aan staat) of de navigatie (altijd: meldingen, tijdelijke en
/// matrixbord-snelheden, open bruggen). Een mislukte ophaalbeurt is een fout;
/// wie `.value` leest houdt dan de vorige laag.
final verkeerLaagProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((
  ref,
) async {
  final config = ref.watch(appConfigProvider);
  if (config == null) return null;
  final interval = ref.watch(onderwegProvider)
      ? verkeerIntervalOnderweg
      : verkeerInterval;
  final ververs = Timer(interval, ref.invalidateSelf);
  ref.onDispose(ververs.cancel);
  final antwoord = await ref
      .watch(dioProvider)
      .get<Map<String, dynamic>>(config.verkeerUrl);
  return antwoord.data;
});

/// De verkeerslaag voor op de kaart, of null als hij daar uit staat.
final verkeerProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final aan = ref.watch(instellingenProvider.select((i) => i.verkeerOpKaart));
  if (!aan) return null;
  return ref.watch(verkeerLaagProvider.future);
});

/// Maximumsnelheden naar tijdstip (OSM `maxspeed:conditional`) per OSM-way;
/// zie [SnelheidTijden]. Leeg als de server ze niet heeft.
final snelheidTijdenProvider = FutureProvider<SnelheidTijden>((ref) async {
  final config = ref.watch(appConfigProvider);
  if (config == null) return SnelheidTijden.leeg;
  final ververs = Timer(const Duration(hours: 6), ref.invalidateSelf);
  ref.onDispose(ververs.cancel);
  try {
    final antwoord = await ref
        .watch(dioProvider)
        .get<Map<String, dynamic>>(config.snelheidTijdenUrl);
    return SnelheidTijden.uitJson(antwoord.data);
  } on DioException {
    return SnelheidTijden.leeg;
  }
});

/// De geplande afsluitingen (GeoJSON met per afsluiting zijn vensters). Pas
/// opgehaald als iemand later wil vertrekken; elk uur ververst, zoals de
/// importer.
final geplandProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final config = ref.watch(appConfigProvider);
  if (config == null) return null;
  final ververs = Timer(const Duration(hours: 1), ref.invalidateSelf);
  ref.onDispose(ververs.cancel);
  final antwoord = await ref
      .watch(dioProvider)
      .get<Map<String, dynamic>>(config.verkeerGeplandUrl);
  return antwoord.data;
});
