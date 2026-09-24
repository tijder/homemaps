import 'dart:async';

import 'package:dio/dio.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/profile.dart';
import '../models/route.dart';
import '../utils/polyline.dart';
import '../utils/timed_speed_limits.dart';

class RouteError implements Exception {
  RouteError(this.code, this.message);

  /// Valhalla's `error_code` (442 = no route found, 171 = no road near a
  /// point), or 0 for a network error.
  final int code;
  final String message;

  @override
  String toString() => 'RouteError($code): $message';
}

/// The speed limit (km/h, null if unknown) and the OSM way of a stretch of
/// route.
typedef StretchLimit = ({int? limit, int? way});

class ValhallaService {
  ValhallaService(this._dio, this.baseUrl);

  final Dio _dio;

  /// For example `https://maps.example.org/valhalla`.
  final String baseUrl;

  static const elevationInterval = 30.0;

  /// The request as JSON. Separate from [route] so it can be tested.
  static Map<String, dynamic> request(
    List<LatLng> points,
    Profile profile, {
    required String language,
    bool liveTraffic = true,
    bool avoidMotorways = false,
    bool avoidTolls = false,
    bool avoidFerries = false,
    bool alternatives = true,
    double? heading,
    DateTime? now,
  }) {
    final live = liveTraffic && profile == Profile.car;
    final options = <String, dynamic>{
      if (avoidMotorways) 'use_highways': 0.0,
      if (avoidTolls) 'use_tolls': 0.0,
      if (avoidFerries) 'use_ferry': 0.0,
      // A time all the same (see date_time below), but without current
      // traffic: only the normal speeds.
      if (profile == Profile.car && !live)
        'speed_types': ['freeflow', 'constrained', 'predicted'],
    };
    return {
      'locations': [
        for (final (i, point) in points.indexed)
          {
            'lat': point.latitude,
            'lon': point.longitude,
            // A waypoint is a place you want to pass, not a stopover:
            // `through` doesn't allow U-turns on the road.
            'type': i == 0 || i == points.length - 1 ? 'break' : 'through',
            // Recalculated en route: depart in the direction you're driving, not
            // with a U-turn because the other way is a few meters shorter.
            if (i == 0 && heading != null) ...{
              'heading': heading.round() % 360,
              'heading_tolerance': 45,
            },
          },
      ],
      'costing': profile.costing,
      if (options.isNotEmpty) 'costing_options': {profile.costing: options},
      'units': 'kilometers',
      'language': language,
      'elevation_interval': elevationInterval,
      // Valhalla only gives alternatives between exactly two points.
      if (alternatives && points.length == 2) 'alternates': 2,
      // Always a time: Valhalla only respects time-restricted access (school
      // streets, delivery windows) if it knows when you're driving; without a
      // time it drives straight through. Not `type: 0` ("depart now"): that
      // goes through the unidirectional search, which gives no alternatives.
      // `type: 3` (one fixed time for the whole route) goes through the
      // bidirectional search. Live traffic (speeds and closures) only counts
      // with the current time, and only for the car (otherwise `speed_types`
      // turns it off); with a later time ([now]) Valhalla phases it out the
      // further away it is. Valhalla reads the time as local time at the
      // departure point.
      'date_time': {'type': 3, 'value': _minuteOf(now ?? DateTime.now())},
    };
  }

  static String _minuteOf(DateTime time) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${twoDigits(time.month)}-${twoDigits(time.day)}'
        'T${twoDigits(time.hour)}:${twoDigits(time.minute)}';
  }

  Future<List<RouteOption>> route(
    List<LatLng> points,
    Profile profile, {
    required String language,
    bool liveTraffic = true,
    bool avoidMotorways = false,
    bool avoidTolls = false,
    bool avoidFerries = false,
    bool alternatives = true,
    double? heading,
    DateTime? departure,
    CancelToken? cancel,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/route',
        data: request(
          points,
          profile,
          language: language,
          liveTraffic: liveTraffic,
          avoidMotorways: avoidMotorways,
          avoidTolls: avoidTolls,
          avoidFerries: avoidFerries,
          alternatives: alternatives,
          heading: heading,
          now: departure,
        ),
        cancelToken: cancel,
      );
      final routes = parseResponse(response.data ?? const {});
      // The delay due to current traffic; it means nothing for departing
      // later.
      final withTraffic =
          liveTraffic && profile == Profile.car && departure == null;
      if (!withTraffic) return routes;
      // For every route at once: how long the same way takes without traffic.
      final normal = await Future.wait([
        for (final route in routes) normalTime(route, profile, cancel),
      ]);
      return [
        for (final (i, route) in routes.indexed)
          route.withNormalTime(normal[i]),
      ];
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      throw _routeError(error);
    }
  }

  /// The travel time of exactly this way without live traffic: see [travelTime].
  Future<double?> normalTime(
    RouteOption route,
    Profile profile, [
    CancelToken? cancel,
  ]) => travelTime(route.points, profile, cancel: cancel);

  /// The travel time along exactly this line: Valhalla map-matches it again
  /// (edge_walk: exactly the same roads). [live]: with current traffic,
  /// otherwise without. Two lines with the same [live] can be compared fairly
  /// this way -- a time from /route is calculated slightly differently. Null if
  /// it fails.
  Future<double?> travelTime(
    List<LatLng> line,
    Profile profile, {
    bool live = false,
    DateTime? now,
    CancelToken? cancel,
  }) async {
    // Between two legs the same point appears twice; drop it.
    final points = <LatLng>[];
    for (final point in line) {
      if (points.isEmpty || points.last != point) points.add(point);
    }
    if (points.length < 2) return null;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/trace_route',
        data: {
          'encoded_polyline': encodePolyline(points),
          'costing': profile.costing,
          'shape_match': 'edge_walk',
          'directions_type': 'none',
          if (live)
            'date_time': {'type': 3, 'value': _minuteOf(now ?? DateTime.now())},
        },
        cancelToken: cancel,
      );
      final time = response.data?['trip']?['summary']?['time'];
      return time is num ? time.toDouble() : null;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      return null;
    }
  }

  /// The speed limit (km/h) and the OSM way per stretch of [line]: element i
  /// belongs to the stretch from point i to i+1; the limit is null if unknown.
  /// The way is for what Valhalla doesn't read: a limit that depends on the
  /// time of day (see [TimedSpeedLimits]). Null if the whole request fails.
  Future<List<StretchLimit>?> speedLimits(
    List<LatLng> line,
    Profile profile, {
    CancelToken? cancel,
  }) async {
    // Drop duplicate points (between two legs), but remember where each
    // original point ended up.
    final points = <LatLng>[];
    final index = <int>[];
    for (final point in line) {
      if (points.isEmpty || points.last != point) points.add(point);
      index.add(points.length - 1);
    }
    if (points.length < 2) return null;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/trace_attributes',
        data: {
          'encoded_polyline': encodePolyline(points),
          'costing': profile.costing,
          'shape_match': 'edge_walk',
          'filters': {
            'attributes': [
              'edge.speed_limit',
              'edge.way_id',
              'edge.begin_shape_index',
              'edge.end_shape_index',
            ],
            'action': 'include',
          },
        },
        cancelToken: cancel,
      );
      final perStretch = List<StretchLimit>.filled(points.length - 1, (
        limit: null,
        way: null,
      ));
      for (final edge in (response.data?['edges'] as List? ?? const [])) {
        if (edge is! Map) continue;
        final limit = edge['speed_limit'], way = edge['way_id'];
        final begin = edge['begin_shape_index'], end = edge['end_shape_index'];
        if (begin is! num || end is! num) continue;
        // Unknown is 0 or missing; "unlimited" (German autobahn) is a string.
        final stretch = (
          limit: limit is num && limit > 0 ? limit.round() : null,
          way: way is num ? way.toInt() : null,
        );
        if (stretch.limit == null && stretch.way == null) continue;
        for (
          var i = begin.toInt();
          i < end.toInt() && i < perStretch.length;
          i++
        ) {
          perStretch[i] = stretch;
        }
      }
      return [
        for (var i = 0; i < line.length - 1; i++)
          perStretch[index[i].clamp(0, perStretch.length - 1)],
      ];
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      return null;
    }
  }

  /// The lanes at the intersections along [line], where OSM has them (and so
  /// Valhalla knows them). Only the OSRM format returns them; `edge_walk` keeps
  /// it to exactly this way. Null if the request fails.
  Future<List<LaneAdvice>?> lanes(
    List<LatLng> line,
    Profile profile, {
    CancelToken? cancel,
  }) async {
    final points = <LatLng>[];
    for (final point in line) {
      if (points.isEmpty || points.last != point) points.add(point);
    }
    if (points.length < 2) return null;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/trace_route',
        data: {
          'encoded_polyline': encodePolyline(points),
          'costing': profile.costing,
          'shape_match': 'edge_walk',
          'format': 'osrm',
        },
        cancelToken: cancel,
      );
      return parseLanes(response.data ?? const {});
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) rethrow;
      return null;
    }
  }

  /// From an OSRM response: every intersection with lanes, in order.
  static List<LaneAdvice> parseLanes(Map<String, dynamic> json) {
    final out = <LaneAdvice>[];
    for (final match in (json['matchings'] as List? ?? const [])) {
      for (final leg in ((match as Map)['legs'] as List? ?? const [])) {
        for (final step in ((leg as Map)['steps'] as List? ?? const [])) {
          for (final junction
              in ((step as Map)['intersections'] as List? ?? const [])) {
            final position = (junction as Map)['location'];
            final perLane = junction['lanes'];
            if (position is! List || position.length < 2 || perLane is! List) {
              continue;
            }
            out.add((
              position: LatLng(
                (position[1] as num).toDouble(),
                (position[0] as num).toDouble(),
              ),
              perLane: [
                for (final lane in perLane.cast<Map>())
                  Lane(
                    directions: [
                      for (final r
                          in (lane['indications'] as List? ?? const []))
                        r as String,
                    ],
                    correct: lane['valid'] == true,
                    usage: lane['valid_indication'] as String?,
                  ),
              ],
            ));
          }
        }
      }
    }
    return out;
  }

  static RouteError _routeError(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['error'] != null) {
      return RouteError(
        (data['error_code'] as num?)?.toInt() ?? 0,
        data['error'].toString(),
      );
    }
    return RouteError(0, error.message ?? error.type.name);
  }

  static List<RouteOption> parseResponse(Map<String, dynamic> json) => [
    RouteOption.fromValhalla(
      (json['trip'] as Map).cast<String, dynamic>(),
      elevationInterval: elevationInterval,
    ),
    for (final alternative in (json['alternates'] as List? ?? const []))
      RouteOption.fromValhalla(
        ((alternative as Map)['trip'] as Map).cast<String, dynamic>(),
        elevationInterval: elevationInterval,
      ),
  ];
}
