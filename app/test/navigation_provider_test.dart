import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/models/place.dart';
import 'package:homemaps/models/profile.dart';
import 'package:homemaps/models/route.dart';
import 'package:homemaps/navigation/navigation_provider.dart';
import 'package:homemaps/navigation/voice.dart';
import 'package:homemaps/navigation/route_tracker.dart';
import 'package:homemaps/providers/services.dart';
import 'package:homemaps/providers/settings.dart';
import 'package:homemaps/providers/location.dart';
import 'package:homemaps/services/valhalla_service.dart';
import 'package:homemaps/utils/distance.dart';
import 'package:homemaps/utils/timed_speed_limits.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'helpers/fake_source.dart' hide fix;
import 'navigation_test.dart' show fix, along, east, stroe;

class FakeVoice implements Voice {
  final sentences = <String>[];

  @override
  Future<void> begin(String language) async {}

  @override
  void say(String sentence) => sentences.add(sentence);

  @override
  Future<void> stop() async {}
}

/// Always returns the same route and remembers the requests.
class FakeValhalla extends ValhallaService {
  FakeValhalla(this.response) : super(Dio(), 'http://fake');

  RouteOption response;

  /// Travel time along a line; unknown by default.
  double? Function(List<LatLng> line) time = (_) => null;

  List<StretchLimit>? limits;

  @override
  Future<List<StretchLimit>?> speedLimits(
    List<LatLng> line,
    Profile profile, {
    CancelToken? cancel,
  }) async => limits;

  @override
  Future<List<LaneAdvice>?> lanes(
    List<LatLng> line,
    Profile profile, {
    CancelToken? cancel,
  }) async => null;

  @override
  Future<double?> travelTime(
    List<LatLng> line,
    Profile profile, {
    bool live = false,
    DateTime? now,
    CancelToken? cancel,
  }) async => time(line);

  /// Called on every request, to capture the state at that moment.
  void Function()? onRequest;
  final requests =
      <({List<LatLng> points, double? heading, bool alternatives})>[];

  @override
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
    onRequest?.call();
    requests.add((
      points: points,
      heading: heading,
      alternatives: alternatives,
    ));
    return [response];
  }
}

final texts = NavTexts(
  language: 'nl-NL',
  notificationHeading: 'Navigating to Voorthuizen',
  notificationBody: 'x',
  recalculating: 'Recalculating route.',
  fasterRoute: (m) => 'Faster route, $m minutes',
  withDistance: (m, sentence) => 'In ${m.round()} m $sentence',
  warning: (kind, m) => 'Caution: $kind in ${(m / 100).round() * 100} m',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final route = stroe();
  final target = Place(label: 'Voorthuizen', point: route.points.last);

  late FakeSource source;
  late FakeVoice voice;
  late FakeValhalla valhalla;
  late ProviderContainer c;

  setUp(() async {
    source = FakeSource(PermissionAnswer.yes);
    voice = FakeVoice();
    valhalla = FakeValhalla(route);
    c = ProviderContainer(
      overrides: [
        locationSourceProvider.overrideWithBuild((_, _) => source),
        voiceProvider.overrideWithValue(voice),
        valhallaProvider.overrideWithValue(valhalla),
      ],
    );
    addTearDown(c.dispose);
    final wait = c.read(locationProvider.notifier).turnOn();
    await Future<void>.delayed(Duration.zero);
    source.fixes.add(fix(route.points.first));
    await wait;
  });

  Future<void> driveTo(LatLng point) async {
    source.fixes.add(fix(point));
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> start() => c
      .read(navigationProvider.notifier)
      .start(route: route, destinations: [target], texts: texts);

  test('start: notification on Android, first sentence, and the state follows along', () async {
    await start();
    expect(source.lastNotification?.title, 'Navigating to Voorthuizen');
    expect(source.lastAccurate, isTrue);
    expect(voice.sentences.first, route.maneuvers.first.voiceImminent);
    final points = along(route.points, 20);
    for (final point in points.take(30)) {
      await driveTo(point);
    }
    final status = c.read(navigationProvider)!.status!;
    expect(status.along, closeTo(29 * 20, 25));
    expect(status.offRoute, isFalse);
  });

  test('off the route: recalculate from here, with your heading', () async {
    await start();
    final points = along(route.points, 20);
    for (final point in points.take(30)) {
      await driveTo(point);
    }
    for (var i = 30; i < 34; i++) {
      source.fixes.add(
        LocationFix(
          point: east(points[i], 200),
          time: DateTime(2026),
          accuracy: 5,
          heading: 90,
          speed: 13,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }
    expect(voice.sentences, contains('Recalculating route.'));
    expect(valhalla.requests, hasLength(1));
    final request = valhalla.requests.single;
    expect(request.heading, 90);
    expect(request.alternatives, isFalse);
    expect(request.points.last, target.point);
    // Not again within ten seconds, even though you're still far away.
    for (var i = 34; i < 38; i++) {
      await driveTo(east(points[i], 200));
    }
    expect(valhalla.requests, hasLength(1));
  });

  test('started far from the start: immediately a route from here', () async {
    // You're 2 km beside the start of the planned route.
    await driveTo(east(route.points.first, 2000));
    int? spokenAtRequest;
    valhalla.onRequest = () => spokenAtRequest ??= voice.sentences.length;
    await start();
    expect(valhalla.requests, hasLength(1));
    expect(
      valhalla.requests.single.points.first.longitude,
      greaterThan(route.points.first.longitude),
    );
    // Don't read out the planned route's instructions first.
    expect(spokenAtRequest, 0);
  });

  test('arrival: "Aangekomen", then no background service anymore', () async {
    await start();
    for (final point in along(route.points, 50)) {
      await driveTo(point);
    }
    final nav = c.read(navigationProvider)!;
    expect(nav.arrived, isTrue);
    expect(voice.sentences.last, 'Aangekomen op je bestemming.');
    expect(source.lastNotification, isNull);
    c.read(navigationProvider.notifier).stop();
    expect(c.read(navigationProvider), isNull);
  });

  group('faster route while driving', () {
    // A "different" route: the same shape, but 500 m shorter, so it counts as a
    // different road.
    final fallback = RouteOption(
      meters: route.meters - 500,
      seconds: route.seconds,
      points: route.points,
      maneuvers: route.maneuvers,
      elevations: const [],
      elevationInterval: 30,
      hasToll: false,
      hasFerry: false,
    );

    Future<void> enRoute() async {
      await start();
      for (final point in along(route.points, 20).take(10)) {
        await driveTo(point);
      }
      valhalla.response = fallback;
    }

    /// The rest of the current route takes [current] s, the new one [newValue] s.
    void times(double current, double newValue) => valhalla.time = (line) =>
        // The new line starts at the start of the route; the rest of the
        // current one where you are now.
        meters(line.first, route.points.first) < 1 ? newValue : current;

    test('a suggestion, and only switch after "Nemen"', () async {
      await enRoute();
      times(1200, 700);
      await c.read(navigationProvider.notifier).searchFaster();
      var nav = c.read(navigationProvider)!;
      expect(nav.suggestion?.secondsFaster, 500);
      expect(nav.route, same(route), reason: 'not switched yet');
      expect(voice.sentences.last, 'Faster route, 8 minutes');

      c.read(navigationProvider.notifier).acceptSuggestion();
      nav = c.read(navigationProvider)!;
      expect(nav.route, same(fallback));
      expect(nav.suggestion, isNull);
    });

    test(
      '"Negeren": the route stays, and the same one does not come back',
      () async {
        await enRoute();
        times(1200, 700);
        await c.read(navigationProvider.notifier).searchFaster();
        c.read(navigationProvider.notifier).ignoreSuggestion();
        expect(c.read(navigationProvider)!.suggestion, isNull);
        expect(c.read(navigationProvider)!.route, same(route));
        await c.read(navigationProvider.notifier).searchFaster();
        expect(c.read(navigationProvider)!.suggestion, isNull);
      },
    );

    test('little gain: no suggestion', () async {
      await enRoute();
      times(1200, 1100); // 100 s: under two minutes
      await c.read(navigationProvider.notifier).searchFaster();
      expect(c.read(navigationProvider)!.suggestion, isNull);
      times(3000, 2800); // 200 s, but less than a tenth
      await c.read(navigationProvider.notifier).searchFaster();
      expect(c.read(navigationProvider)!.suggestion, isNull);
    });
  });

  test('speed limit of the stretch you are driving on', () async {
    valhalla.limits = [
      for (var i = 0; i < route.points.length - 1; i++)
        (limit: i < 10 ? 60 : 80, way: null),
    ];
    await start();
    await Future<void>.delayed(Duration.zero);
    await driveTo(route.points[2]);
    expect(c.read(navigationProvider)!.limit, 60);
    for (final point in along(route.points, 20).take(80)) {
      await driveTo(point);
    }
    final nav = c.read(navigationProvider)!;
    expect(nav.status!.segment, greaterThanOrEqualTo(10));
    expect(nav.limit, 80);
  });

  test('a temporary speed limit wins when it is lower', () async {
    valhalla.limits = [
      for (var i = 0; i < route.points.length - 1; i++) (limit: 50, way: null),
    ];
    final roadworks = route.points.sublist(0, 16);
    c.dispose();
    c = ProviderContainer(
      overrides: [
        locationSourceProvider.overrideWithBuild((_, _) => source),
        voiceProvider.overrideWithValue(voice),
        valhallaProvider.overrideWithValue(valhalla),
        trafficLayerProvider.overrideWithValue(
          AsyncData({
            'type': 'FeatureCollection',
            'features': [
              {
                'type': 'Feature',
                'id': 0,
                'properties': {'kind': 'speed_limit', 'kph': 30},
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    for (final p in roadworks) [p.longitude, p.latitude],
                  ],
                },
              },
            ],
          }),
        ),
      ],
    );
    addTearDown(c.dispose);
    final wait = c.read(locationProvider.notifier).turnOn();
    await Future<void>.delayed(Duration.zero);
    source.fixes.add(fix(route.points.first));
    await wait;
    await start();
    await Future<void>.delayed(Duration.zero);
    await driveTo(route.points[2]);
    var nav = c.read(navigationProvider)!;
    expect(nav.limit, 30);
    expect(nav.limitSource, LimitSource.roadworks);
    // Past the roadworks: back to the normal 50.
    for (final point in along(route.points, 20).take(80)) {
      await driveTo(point);
    }
    nav = c.read(navigationProvider)!;
    expect(nav.status!.segment, greaterThanOrEqualTo(16));
    expect(nav.limit, 50);
    expect(nav.limitSource, LimitSource.osm);
  });

  Future<void> withLayer(
    List<Map<String, dynamic>> features, {
    TimedSpeedLimits times = TimedSpeedLimits.empty,
  }) async {
    c.dispose();
    c = ProviderContainer(
      overrides: [
        locationSourceProvider.overrideWithBuild((_, _) => source),
        voiceProvider.overrideWithValue(voice),
        valhallaProvider.overrideWithValue(valhalla),
        trafficLayerProvider.overrideWithValue(
          AsyncData({'type': 'FeatureCollection', 'features': features}),
        ),
        timedSpeedLimitsProvider.overrideWithValue(AsyncData(times)),
      ],
    );
    addTearDown(c.dispose);
    final wait = c.read(locationProvider.notifier).turnOn();
    await Future<void>.delayed(Duration.zero);
    source.fixes.add(fix(route.points.first));
    await wait;
  }

  test('a time-dependent limit: the rule that applies now', () async {
    valhalla.limits = [
      for (var i = 0; i < route.points.length - 1; i++) (limit: 100, way: 7),
    ];
    // A rule that always applies: this does not depend on the test's clock.
    await withLayer(
      const [],
      times: TimedSpeedLimits.fromJson({
        'ways': {
          '7': [
            [
              130,
              127,
              [
                [0, 1440],
              ],
            ],
          ],
        },
      }),
    );
    await start();
    await Future<void>.delayed(Duration.zero);
    await driveTo(route.points[2]);
    final nav = c.read(navigationProvider)!;
    expect(nav.limit, 130);
    expect(nav.limitSource, LimitSource.timeOfDay);
  });

  test('MSI signs take precedence, until a blank gantry', () async {
    valhalla.limits = [
      for (var i = 0; i < route.points.length - 1; i++) (limit: 80, way: null),
    ];
    final tracker = RouteTracker(route);
    Map<String, dynamic> gantry(int i, List<String> perLane) {
      final position = tracker.locate(route.points[i]);
      return {
        'type': 'Feature',
        'properties': {
          'kind': 'msi',
          'bearing': position.heading,
          'lanes': perLane,
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [route.points[i].longitude, route.points[i].latitude],
        },
      };
    }

    await withLayer([
      gantry(3, ['50r', 'x']),
      gantry(30, ['', '']),
    ]);
    await start();
    await Future<void>.delayed(Duration.zero);
    await driveTo(route.points[1]);
    // Still before the gantry: the normal limit, and the gantry shown.
    var nav = c.read(navigationProvider)!;
    expect(nav.limit, 80);
    expect(nav.matrix?.perLane, ['50r', 'x']);
    await driveTo(route.points[6]);
    nav = c.read(navigationProvider)!;
    expect(nav.limit, 50);
    expect(nav.limitSource, LimitSource.msi);
    expect(nav.matrix, isNull); // the next one is blank
    for (final point in along(route.points, 20).take(80)) {
      await driveTo(point);
    }
    nav = c.read(navigationProvider)!;
    expect(nav.status!.segment, greaterThan(30));
    expect(nav.limit, 80);
    expect(nav.limitSource, LimitSource.osm);
  });

  test('an open bridge on the route: warned once', () async {
    final bridge = along(route.points, 20)[50];
    await withLayer([
      {
        'type': 'Feature',
        'id': 0,
        'properties': {'kind': 'bridge'},
        'geometry': {
          'type': 'Point',
          'coordinates': [bridge.longitude, bridge.latitude],
        },
      },
    ]);
    await start();
    for (final p in along(route.points, 20).take(30)) {
      await driveTo(p);
    }
    expect(voice.sentences.where((z) => z.startsWith('Caution')), [
      'Caution: bridge in 1000 m',
    ]);
  });

  test('an accident ahead of you on the route: warned once', () async {
    // The accident is 1500 m further along the route; a breakdown on the other
    // carriageway (against the direction of travel) doesn't count.
    final points = along(route.points, 20);
    final accident = points[75], breakdown = points[76];
    Map<String, dynamic> point(
      int id,
      String kind,
      LatLng p, [
      double? heading,
    ]) => {
      'type': 'Feature',
      'id': id,
      'properties': {'kind': kind, 'bearing': ?heading},
      'geometry': {
        'type': 'Point',
        'coordinates': [p.longitude, p.latitude],
      },
    };
    c.dispose();
    c = ProviderContainer(
      overrides: [
        locationSourceProvider.overrideWithBuild((_, _) => source),
        voiceProvider.overrideWithValue(voice),
        valhallaProvider.overrideWithValue(valhalla),
        trafficLayerProvider.overrideWithValue(
          AsyncData({
            'type': 'FeatureCollection',
            'features': [
              point(0, 'accident', accident),
              point(1, 'breakdown', breakdown, 180),
            ],
          }),
        ),
      ],
    );
    addTearDown(c.dispose);
    final wait = c.read(locationProvider.notifier).turnOn();
    await Future<void>.delayed(Duration.zero);
    source.fixes.add(fix(route.points.first));
    await wait;
    c.read(settingsProvider);
    await start();
    for (final p in points.take(60)) {
      await driveTo(p);
    }
    final warnings = voice.sentences.where((z) => z.startsWith('Caution'));
    // Already within 2 km at departure: immediately, and not again after that.
    expect(warnings, ['Caution: accident in 1500 m']);
  });
}
