import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/app_config.dart';
import '../services/along_route.dart';
import '../services/photon_service.dart';
import '../services/valhalla_service.dart';
import '../utils/night_style.dart';
import '../utils/timed_speed_limits.dart';
import 'settings.dart';

final dioProvider = Provider<Dio>(
  (ref) => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
    ),
  ),
);

/// The contents of `/config.json`, only on the web. Loaded in main() and
/// overridden here; a missing or empty file is simply `{}`.
final webConfigProvider = Provider<Map<String, dynamic>>((ref) => const {});

/// Null as long as no server has been set on Android yet.
final appConfigProvider = Provider<AppConfig?>((ref) {
  if (kIsWeb) {
    // The app is served by the same nginx that proxies the backends.
    final base = Uri.base.resolve('.').toString();
    return AppConfig.fromServer(base, ref.watch(webConfigProvider));
  }
  final server = ref.watch(settingsProvider.select((s) => s.server));
  return server.isEmpty ? null : AppConfig.fromServer(server);
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

final alongRouteProvider = Provider<AlongRouteService?>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config == null) return null;
  return AlongRouteService(
    ref.watch(dioProvider),
    config.tilesUrl,
    config.valhallaUrl,
  );
});

/// Where the map opens: the `center` from the TileJSON of the own tileserver, so
/// that an installation for another region doesn't start on the Netherlands. If
/// that fails, the Netherlands is the fallback.
final mapStartProvider = FutureProvider<CameraPosition>((ref) async {
  const fallbackPosition = CameraPosition(target: LatLng(52.2, 5.3), zoom: 6.5);
  final config = ref.watch(appConfigProvider);
  if (config == null) return fallbackPosition;
  try {
    final response = await ref
        .watch(dioProvider)
        .get<Map<String, dynamic>>(
          '${config.tilesUrl}/data/v3.json',
          options: Options(receiveTimeout: const Duration(seconds: 5)),
        );
    final center = (response.data?['center'] as List?)?.cast<num>();
    if (center == null || center.length < 2) return fallbackPosition;
    return CameraPosition(
      target: LatLng(center[1].toDouble(), center[0].toDouble()),
      zoom: center.length > 2 ? center[2].toDouble() : 7,
    );
  } on Object {
    return fallbackPosition;
  }
});

/// How often the traffic layer is refreshed; the importer rebuilds it every
/// five minutes.
const trafficInterval = Duration(minutes: 5);

/// More often en route: the importer refreshes the MSI signs above the
/// motorway every minute.
const trafficIntervalEnRoute = Duration(minutes: 1);

/// Whether navigation is running; the navigation sets it. Then the traffic
/// layer refreshes more often.
final enRouteProvider = NotifierProvider<EnRouteNotifier, bool>(
  EnRouteNotifier.new,
);

class EnRouteNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void apply(bool enRoute) => state = enRoute;
}

/// The traffic layer as GeoJSON, as long as someone uses it: the map (if it is
/// on there) or the navigation (always: incidents, temporary and MSI speed
/// limits, open bridges). A failed fetch is an error; whoever reads `.value`
/// then keeps the previous layer.
final trafficLayerProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((
  ref,
) async {
  final config = ref.watch(appConfigProvider);
  if (config == null) return null;
  final interval = ref.watch(enRouteProvider)
      ? trafficIntervalEnRoute
      : trafficInterval;
  final refresh = Timer(interval, ref.invalidateSelf);
  ref.onDispose(refresh.cancel);
  final response = await ref
      .watch(dioProvider)
      .get<Map<String, dynamic>>(config.trafficUrl);
  return response.data;
});

/// The traffic layer for the map, or null if it is off there.
final trafficProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final enabled = ref.watch(settingsProvider.select((s) => s.trafficOnMap));
  if (!enabled) return null;
  return ref.watch(trafficLayerProvider.future);
});

/// The night version of a map style (see [nightStyle]), as JSON for
/// MapLibre. Fetched and converted once per style.
final nightStyleProvider = FutureProvider.family<String, String>((
  ref,
  url,
) async {
  final response = await ref.watch(dioProvider).get<Map<String, dynamic>>(url);
  final style = response.data;
  if (style == null) throw StateError('empty style: $url');
  return jsonEncode(nightStyle(style));
});

/// Speed limits by time of day (OSM `maxspeed:conditional`) per OSM way;
/// see [TimedSpeedLimits]. Empty if the server doesn't have them.
final timedSpeedLimitsProvider = FutureProvider<TimedSpeedLimits>((ref) async {
  final config = ref.watch(appConfigProvider);
  if (config == null) return TimedSpeedLimits.empty;
  final refresh = Timer(const Duration(hours: 6), ref.invalidateSelf);
  ref.onDispose(refresh.cancel);
  try {
    final response = await ref
        .watch(dioProvider)
        .get<Map<String, dynamic>>(config.conditionalSpeedsUrl);
    return TimedSpeedLimits.fromJson(response.data);
  } on DioException {
    return TimedSpeedLimits.empty;
  }
});

/// Speed cameras, average speed sections and red light cameras (GeoJSON from
/// `/enforcement`), or null if they are turned off. The importer reads them
/// from OSM when the map is rebuilt; every six hours is plenty. A failed fetch
/// is an error (`.value` keeps the previous layer) and is retried sooner.
final enforcementProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final config = ref.watch(appConfigProvider);
  final enabled = ref.watch(settingsProvider.select((s) => s.speedCameras));
  if (config == null || !enabled) return null;
  var refresh = Timer(const Duration(hours: 6), ref.invalidateSelf);
  ref.onDispose(() => refresh.cancel());
  try {
    final response = await ref
        .watch(dioProvider)
        .get<Map<String, dynamic>>(config.enforcementUrl);
    return response.data;
  } on DioException {
    refresh.cancel();
    refresh = Timer(const Duration(minutes: 5), ref.invalidateSelf);
    rethrow;
  }
});

/// The planned closures (GeoJSON with each closure's windows). Only fetched
/// once someone wants to leave later; refreshed every hour, like the
/// importer.
final plannedProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final config = ref.watch(appConfigProvider);
  if (config == null) return null;
  final refresh = Timer(const Duration(hours: 1), ref.invalidateSelf);
  ref.onDispose(refresh.cancel);
  final response = await ref
      .watch(dioProvider)
      .get<Map<String, dynamic>>(config.trafficPlannedUrl);
  return response.data;
});
