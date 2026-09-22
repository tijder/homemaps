import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/models/profiel.dart';
import 'package:homemaps/services/langs_route.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Tegel 14/8446/5405 is de echte tegel rond Barneveld (met de Esso De
/// Stroet), de andere zijn leeg; de matrix geeft vaste tijden.
class NepServer implements HttpClientAdapter {
  final tegel = File('test/fixtures/tegel_14_8446_5405.pbf').readAsBytesSync();
  final verzoeken = <String>[];
  Map<String, dynamic>? matrixVerzoek;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    verzoeken.add(options.path);
    if (options.path.endsWith('.pbf')) {
      // Alleen de tegel zelf; de buren zijn leeg.
      final bytes = options.path.endsWith('/14/8446/5405.pbf')
          ? tegel
          : Uint8List(0);
      return ResponseBody.fromBytes(
        bytes,
        200,
        headers: {
          Headers.contentTypeHeader: ['application/x-protobuf'],
        },
      );
    }
    matrixVerzoek = options.data as Map<String, dynamic>;
    final stops = (matrixVerzoek!['sources'] as List).length - 1;
    // van -> stop 300 s, stop -> naar 400 s, van -> naar direct 600 s.
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
  test('tanken langs een weg vlak bij de Esso: één stop, met omweg', () async {
    final server = NepServer();
    final dio = Dio()..httpClientAdapter = server;
    final dienst = LangsRouteService(
      dio,
      'http://nep/tiles',
      'http://nep/valhalla',
    );
    // Een rechte lijn van west naar oost, 200 m ten zuiden van de Esso
    // (52.0872, 5.6002).
    final lijn = [const LatLng(52.0854, 5.585), const LatLng(52.0854, 5.615)];
    final treffers = await dienst.zoek(
      lijn,
      Categorie.tanken,
      profiel: Profiel.auto,
      naamZonderNaam: 'Tankstation',
    );
    expect(treffers, hasLength(1));
    expect(treffers.single.plaats.naam, 'Esso De Stroet');
    expect(treffers.single.afstandTotRoute, closeTo(200, 20));
    // 300 + 400 - 600.
    expect(treffers.single.omwegSeconden, 100);
    expect(
      server.verzoeken.where((p) => p.endsWith('.pbf')).length,
      greaterThan(1),
    );
    expect(server.matrixVerzoek!['costing'], 'auto');
  });

  test('niets in de buurt: leeg, en geen matrixverzoek', () async {
    final server = NepServer();
    final dio = Dio()..httpClientAdapter = server;
    final dienst = LangsRouteService(
      dio,
      'http://nep/tiles',
      'http://nep/valhalla',
    );
    final treffers = await dienst.zoek(
      [const LatLng(52.0854, 5.585), const LatLng(52.0854, 5.615)],
      Categorie.laden,
      profiel: Profiel.auto,
      naamZonderNaam: 'Laadpunt',
    );
    expect(treffers, isEmpty);
    expect(server.matrixVerzoek, isNull);
  });
}
