import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/models/profile.dart';
import 'package:homemaps/models/route.dart';
import 'package:homemaps/services/valhalla_service.dart';
import 'package:homemaps/utils/polyline.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  const a = LatLng(52.09, 5.12), b = LatLng(52.2, 5.0), c = LatLng(52.37, 4.89);

  test('two points: alternatives and live traffic for the car', () {
    final v = ValhallaService.request(
      [a, c],
      Profile.car,
      language: 'nl-NL',
      now: DateTime(2026, 9, 22, 8, 5, 59),
    );
    expect(v['alternates'], 2);
    // Type 3, not 0: only then do alternatives come, with live traffic.
    expect(v['date_time'], {'type': 3, 'value': '2026-09-22T08:05'});
    expect(v['costing'], 'auto');
    expect((v['locations'] as List).map((l) => l['type']), ['break', 'break']);
  });

  test('via points: no alternatives, intermediate point is through', () {
    final v = ValhallaService.request(
      [a, b, c],
      Profile.car,
      language: 'nl-NL',
    );
    expect(v.containsKey('alternates'), isFalse);
    expect((v['locations'] as List).map((l) => l['type']), [
      'break',
      'through',
      'break',
    ]);
  });

  test('always a time (school streets), live traffic only for the car', () {
    final now = DateTime(2026, 9, 29, 8, 0);
    final bike = ValhallaService.request(
      [a, c],
      Profile.bike,
      language: 'nl-NL',
      now: now,
    );
    expect(bike['date_time'], {'type': 3, 'value': '2026-09-29T08:00'});
    expect(bike.containsKey('costing_options'), isFalse);
    // Car without live traffic: the time yes, but not the current traffic.
    final without = ValhallaService.request(
      [a, c],
      Profile.car,
      language: 'nl-NL',
      liveTraffic: false,
      now: now,
    );
    expect(without['date_time'], {'type': 3, 'value': '2026-09-29T08:00'});
    expect(without['costing_options'], {
      'auto': {
        'speed_types': ['freeflow', 'constrained', 'predicted'],
      },
    });
  });

  test('avoiding becomes a costing option', () {
    final car = ValhallaService.request(
      [a, c],
      Profile.car,
      language: 'nl-NL',
      avoidMotorways: true,
      avoidFerries: true,
    );
    expect(car['costing_options'], {
      'auto': {'use_highways': 0.0, 'use_ferry': 0.0},
    });
  });

  test('polyline with six decimals', () {
    // Utrecht -> Amsterdam, encoded with precision 6 (Google's format uses 5).
    final points = decodePolyline('wsjjbBovqwH_qfP~s~L');
    expect(points, hasLength(2));
    expect(points[0].latitude, closeTo(52.0907, 1e-9));
    expect(points[0].longitude, closeTo(5.1214, 1e-9));
    expect(points[1].latitude, closeTo(52.3731, 1e-9));
    expect(points[1].longitude, closeTo(4.8922, 1e-9));
  });

  test('polyline with negative steps (broke in the JavaScript build)', () {
    // Also run this with `flutter test --platform chrome`: only there does a
    // bit operation behave as in the browser.
    final points = decodePolyline('onlapA_t{{And@~p@~WnKnKod@');
    expect(points, hasLength(4));
    expect(points[1].latitude, closeTo(42.5064, 1e-6));
    expect(points[1].longitude, closeTo(1.5212, 1e-6));
    expect(points[3].latitude, closeTo(42.5058, 1e-6));
    expect(points[3].longitude, closeTo(1.5216, 1e-6));
  });

  test('response with alternative, two legs and elevation', () {
    Map<String, dynamic> trip(double km, List<Map<String, dynamic>> legs) => {
      'summary': {
        'length': km,
        'time': km * 60,
        'has_toll': false,
        'has_ferry': true,
      },
      'legs': legs,
    };
    final leg = {
      'shape': 'wsjjbBovqwH_qfP~s~L',
      'elevation': [10, 14, 12],
      'maneuvers': [
        {
          'instruction': 'Rijd naar het noorden.',
          'type': 1,
          'length': 1.5,
          'time': 90,
          'begin_shape_index': 0,
        },
        {
          'instruction': 'U bent aangekomen.',
          'type': 4,
          'length': 0,
          'time': 0,
          'begin_shape_index': 1,
        },
      ],
    };
    final routes = ValhallaService.parseResponse({
      'trip': trip(12.5, [leg, leg]),
      'alternates': [
        {
          'trip': trip(15, [leg]),
        },
      ],
    });
    expect(routes, hasLength(2));
    expect(routes[0].meters, 12500);
    expect(routes[0].points, hasLength(4));
    // The second leg continues counting in the shape.
    expect(routes[0].maneuvers[2].shapeIndex, 2);
    expect(routes[0].elevations, [10, 14, 12, 10, 14, 12]);
    expect(routes[0].ascent, 8);
    expect(routes[0].descent, 6);
    expect(routes[0].hasFerry, isTrue);
    expect(routes[1].meters, 15000);
  });

  test('encoding a polyline is the inverse of decoding', () {
    // The same example as above, now the other way round.
    expect(
      encodePolyline(const [LatLng(52.0907, 5.1214), LatLng(52.3731, 4.8922)]),
      'wsjjbBovqwH_qfP~s~L',
    );
    // Also negative (south, west) and with small steps.
    const points = [
      LatLng(-33.868820, 151.209290),
      LatLng(-33.868821, 151.209289),
      LatLng(40.712776, -74.005974),
    ];
    final back = decodePolyline(encodePolyline(points));
    for (final (i, point) in points.indexed) {
      expect(back[i].latitude, closeTo(point.latitude, 1e-9));
      expect(back[i].longitude, closeTo(point.longitude, 1e-9));
    }
  });

  test('delay: live minus normal, never negative, zero without data', () {
    RouteOption r(double seconds, double? normal) => RouteOption(
      meters: 1000,
      seconds: seconds,
      points: const [],
      maneuvers: const [],
      elevations: const [],
      elevationInterval: 30,
      hasToll: false,
      hasFerry: false,
      normalSeconds: normal,
    );
    expect(r(2500, 2000).delay, 500);
    expect(r(1900, 2000).delay, 0);
    expect(r(2500, null).delay, 0);
    expect(r(2500, null).withNormalTime(2400).delay, 100);
  });
}
