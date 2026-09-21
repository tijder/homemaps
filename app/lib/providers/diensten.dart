import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/app_config.dart';
import '../services/photon_service.dart';
import '../services/valhalla_service.dart';
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
