import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/models/profile.dart';
import 'package:homemaps/services/along_route.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Tile 14/8446/5405 is the real tile around Barneveld (with the Esso De
/// Stroet), the others are empty; the matrix returns fixed times.
class FakeServer implements HttpClientAdapter {
  final tile = File('test/fixtures/tile_14_8446_5405.pbf').readAsBytesSync();
  final requests = <String>[];
  Map<String, dynamic>? matrixRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.path);
    if (options.path.endsWith('.pbf')) {
      // Only the tile itself; the neighbours are empty.
      final bytes = options.path.endsWith('/14/8446/5405.pbf')
          ? tile
          : Uint8List(0);
      return ResponseBody.fromBytes(
        bytes,
        200,
        headers: {
          Headers.contentTypeHeader: ['application/x-protobuf'],
        },
      );
    }
    matrixRequest = options.data as Map<String, dynamic>;
    final stops = (matrixRequest!['sources'] as List).length - 1;
    // from -> stop 300 s, stop -> to 400 s, from -> to direct 600 s.
    final matrix = [
      [
        for (var i = 0; i < stops; i++) {'time': 300},
        {'time': 600},
      ],
      for (var i = 0; i < stops; i++)
        [
          for (var j = 0; j < stops; j++) {'time': 0},
          {'time': 400},
        ],
    ];
    return ResponseBody.fromString(
      jsonEncode({'sources_to_targets': matrix}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'refuelling along a road close to the Esso: one stop, with detour',
    () async {
      final server = FakeServer();
      final dio = Dio()..httpClientAdapter = server;
      final service = AlongRouteService(
        dio,
        'http://fake/tiles',
        'http://fake/valhalla',
      );
      // A straight line from west to east, 200 m south of the Esso
      // (52.0872, 5.6002).
      final line = [const LatLng(52.0854, 5.585), const LatLng(52.0854, 5.615)];
      final hits = await service.search(
        line,
        PoiCategory.fuel,
        profile: Profile.car,
        unnamedLabel: 'Tankstation',
      );
      expect(hits, hasLength(1));
      expect(hits.single.place.label, 'Esso De Stroet');
      expect(hits.single.distanceToRoute, closeTo(200, 20));
      // 300 + 400 - 600.
      expect(hits.single.detourSeconds, 100);
      expect(
        server.requests.where((p) => p.endsWith('.pbf')).length,
        greaterThan(1),
      );
      expect(server.matrixRequest!['costing'], 'auto');
    },
  );

  test('nothing nearby: empty, and no matrix request', () async {
    final server = FakeServer();
    final dio = Dio()..httpClientAdapter = server;
    final service = AlongRouteService(
      dio,
      'http://fake/tiles',
      'http://fake/valhalla',
    );
    final hits = await service.search(
      [const LatLng(52.0854, 5.585), const LatLng(52.0854, 5.615)],
      PoiCategory.charging,
      profile: Profile.car,
      unnamedLabel: 'Laadpunt',
    );
    expect(hits, isEmpty);
    expect(server.matrixRequest, isNull);
  });
}
