import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/place.dart';
import '../models/profile.dart';
import '../utils/distance.dart';
import '../utils/mvt.dart';

/// What you can search for along the route, with the classes from
/// OpenMapTiles' `poi` layer (class/subclass).
enum PoiCategory {
  fuel,
  charging,
  supermarket,
  food;

  bool matches(Map<String, Object?> poi) => switch (this) {
    fuel => poi['class'] == 'fuel' && poi['subclass'] == 'fuel',
    charging => poi['subclass'] == 'charging_station',
    supermarket => poi['subclass'] == 'supermarket',
    food => const {'restaurant', 'fast_food', 'cafe'}.contains(poi['class']),
  };
}

class AlongRouteHit {
  const AlongRouteHit(this.place, this.distanceToRoute, this.detourSeconds);

  final Place place;
  final double distanceToRoute;

  /// How much longer the trip gets with this stop; null if Valhalla couldn't
  /// tell.
  final double? detourSeconds;
}

/// Searches our own vector tiles for places right along a route, and has
/// Valhalla work out how much of a detour each stop costs.
class AlongRouteService {
  AlongRouteService(this._dio, this.tilesUrl, this.valhallaUrl);

  final Dio _dio;
  final String tilesUrl;
  final String valhallaUrl;

  static const _zoom = 14;

  /// [line]: the route from where you are now. Only the first [maxLength]
  /// meters count: a fuel station 200 km further on doesn't help now.
  Future<List<AlongRouteHit>> search(
    List<LatLng> line,
    PoiCategory category, {
    required Profile profile,
    required String unnamedLabel,
    double maxDistance = 1000,
    double maxLength = 80000,
    int maxCandidates = 20,
    CancelToken? cancel,
  }) async {
    final stretch = _begin(line, maxLength);
    if (stretch.length < 2) return const [];

    // Tiles in a band of ~700 m around the route.
    final tiles = <(int, int)>{};
    for (final point in _every(stretch, 400)) {
      final margin = 700 / 111320;
      final lonMargin = margin / cos(point.latitude * pi / 180);
      final (x0, y0) = _tile(
        point.latitude + margin,
        point.longitude - lonMargin,
      );
      final (x1, y1) = _tile(
        point.latitude - margin,
        point.longitude + lonMargin,
      );
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          tiles.add((x, y));
        }
      }
      if (tiles.length > 150) break;
    }

    final seen = <String>{};
    final candidates = <(TilePoint, double)>[];
    final list = tiles.toList();
    // In groups of eight at a time: enough to be fast, not so many that the
    // tileserver notices.
    for (var i = 0; i < list.length; i += 8) {
      final group = list.skip(i).take(8);
      final results = await Future.wait([
        for (final (x, y) in group) _poi(x, y, cancel),
      ]);
      for (final poi in results.expand((r) => r)) {
        if (!category.matches(poi.properties)) continue;
        // A point close to the edge is in several tiles.
        final key =
            '${poi.properties['name']}@${poi.point.latitude.toStringAsFixed(4)},'
            '${poi.point.longitude.toStringAsFixed(4)}';
        if (!seen.add(key)) continue;
        final distance = metersToLine(poi.point, stretch);
        if (distance <= maxDistance) candidates.add((poi, distance));
      }
    }
    candidates.sort((a, b) => a.$2.compareTo(b.$2));
    final best = candidates.take(maxCandidates).toList();
    if (best.isEmpty) return const [];

    final detours = await _detours(
      stretch.first,
      line.last,
      [for (final (poi, _) in best) poi.point],
      profile,
      cancel,
    );
    final out = [
      for (final (i, (poi, distance)) in best.indexed)
        AlongRouteHit(
          Place(
            label:
                (poi.properties['name'] as String?)?.trim().isNotEmpty == true
                ? poi.properties['name'] as String
                : unnamedLabel,
            point: poi.point,
          ),
          distance,
          detours?[i],
        ),
    ];
    out.sort(
      (a, b) => (a.detourSeconds ?? a.distanceToRoute).compareTo(
        b.detourSeconds ?? b.distanceToRoute,
      ),
    );
    return out;
  }

  Future<List<TilePoint>> _poi(int x, int y, CancelToken? cancel) async {
    try {
      final response = await _dio.get<List<int>>(
        '$tilesUrl/data/v3/$_zoom/$x/$y.pbf',
        options: Options(responseType: ResponseType.bytes),
        cancelToken: cancel,
      );
      final data = response.data;
      // Empty (sea) or still compressed: then nothing. The browser and Dart
      // unpack gzip with Content-Encoding themselves.
      if (data == null ||
          data.length < 2 ||
          (data[0] == 0x1f && data[1] == 0x8b)) {
        return const [];
      }
      return pointsFromTile(
        Uint8List.fromList(data),
        layer: 'poi',
        z: _zoom,
        x: x,
        y: y,
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      return const [];
    } on FormatException {
      return const [];
    }
  }

  /// Per candidate: (from → stop) + (stop → to) − (from → to), with one
  /// matrix request.
  Future<List<double?>?> _detours(
    LatLng from,
    LatLng to,
    List<LatLng> stops,
    Profile profile,
    CancelToken? cancel,
  ) async {
    Map<String, double> position(LatLng p) => {
      'lat': p.latitude,
      'lon': p.longitude,
    };
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$valhallaUrl/sources_to_targets',
        data: {
          'sources': [position(from), for (final s in stops) position(s)],
          'targets': [for (final s in stops) position(s), position(to)],
          'costing': profile.costing,
        },
        cancelToken: cancel,
      );
      final matrix = response.data?['sources_to_targets'] as List?;
      if (matrix == null) return null;
      double? time(int source, int target) {
        final value = ((matrix[source] as List)[target] as Map)['time'];
        return value is num ? value.toDouble() : null;
      }

      final direct = time(0, stops.length);
      if (direct == null) return null;
      return [
        for (var i = 0; i < stops.length; i++)
          switch ((time(0, i), time(i + 1, stops.length))) {
            (final outbound?, final back?) => max(0, outbound + back - direct),
            _ => null,
          },
      ];
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      return null;
    }
  }

  static (int, int) _tile(double lat, double lon) {
    final n = pow(2, _zoom);
    final x = ((lon + 180) / 360 * n).floor();
    final r = lat * pi / 180;
    final y = ((1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * n).floor();
    return (x, y);
  }

  static List<LatLng> _begin(List<LatLng> line, double length) {
    final out = <LatLng>[];
    var travelled = 0.0;
    for (final (i, p) in line.indexed) {
      if (i > 0) travelled += meters(line[i - 1], p);
      out.add(p);
      if (travelled > length) break;
    }
    return out;
  }

  /// Points every [step] meters along [line] (also in the middle of long
  /// straight stretches), plus the last one.
  static Iterable<LatLng> _every(List<LatLng> line, double step) sync* {
    yield line.first;
    var offset = step;
    for (var i = 1; i < line.length; i++) {
      final a = line[i - 1], b = line[i];
      final stretch = meters(a, b);
      var at = offset;
      while (at <= stretch) {
        final t = at / stretch;
        yield LatLng(
          a.latitude + t * (b.latitude - a.latitude),
          a.longitude + t * (b.longitude - a.longitude),
        );
        at += step;
      }
      offset = at - stretch;
    }
    yield line.last;
  }
}
