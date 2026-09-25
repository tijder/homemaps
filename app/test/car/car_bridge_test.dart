import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/car/car_api.g.dart';
import 'package:homemaps/car/car_bridge.dart';
import 'package:homemaps/models/app_config.dart';
import 'package:homemaps/models/place.dart';
import 'package:homemaps/models/route.dart';
import 'package:homemaps/navigation/navigation_provider.dart';
import 'package:homemaps/navigation/simulation.dart';
import 'package:homemaps/navigation/voice.dart';
import 'package:homemaps/providers/location.dart';
import 'package:homemaps/providers/planner.dart';
import 'package:homemaps/providers/saved_places.dart';
import 'package:homemaps/providers/services.dart';
import 'package:homemaps/services/photon_service.dart';
import 'package:homemaps/utils/distance.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../helpers/fake_car_host.dart';
import '../helpers/fake_source.dart' hide fix;
import '../navigation_provider_test.dart' show FakeValhalla, FakeVoice;
import '../navigation_test.dart' show along, fix, stroe;

class FakePhoton extends PhotonService {
  FakePhoton(this.results) : super(Dio(), 'http://fake');

  final List<Place> results;
  final searched = <String>[];

  @override
  Future<List<Place>> search(
    String text, {
    LatLng? near,
    CancelToken? cancel,
  }) async {
    searched.add(text);
    return results;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final route = stroe();
  final target = Place(label: 'Voorthuizen', point: route.points.last);
  final surface = CarSurface(
    width: 800,
    height: 480,
    density: 1,
    dark: false,
    platform: 'androidauto',
  );

  late FakeSource source;
  late FakeCarHost host;
  late FakeValhalla valhalla;
  late FakePhoton photon;
  late ProviderContainer c;
  late CarBridge bridge;

  setUp(() {
    source = FakeSource(PermissionAnswer.yes);
    host = FakeCarHost();
    valhalla = FakeValhalla(route);
    photon = FakePhoton([target]);
    c = ProviderContainer(
      overrides: [
        locationSourceProvider.overrideWithBuild((_, _) => source),
        voiceProvider.overrideWithValue(FakeVoice()),
        valhallaProvider.overrideWithValue(valhalla),
        photonProvider.overrideWithValue(photon),
        appConfigProvider.overrideWithValue(
          AppConfig.fromServer('https://maps.example.org'),
        ),
        carHostProvider.overrideWithValue(host),
      ],
    );
    addTearDown(c.dispose);
    bridge = c.read(carBridgeProvider);
  });

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Drawing the icons takes real time; wait until [ready], at most 5 s.
  Future<void> waitFor(bool Function() ready) async {
    final until = DateTime.now().add(const Duration(seconds: 5));
    while (!ready() && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> driveTo(LatLng point) async {
    source.fixes.add(fix(point));
    await settle();
  }

  /// Turns the location on with a fix at the start of the route.
  Future<void> locate() async {
    final wait = c.read(locationProvider.notifier).turnOn();
    await Future<void>.delayed(Duration.zero);
    source.fixes.add(fix(route.points.first));
    await wait;
    await settle();
  }

  test('says it is ready, and nothing else before a car connects', () {
    expect(host.names, ['ready']);
  });

  test('connect: texts, style, images and the home screen', () async {
    c.read(savedPlacesProvider.notifier).setHome(target);
    bridge.connected(surface);
    await settle();
    expect(host.names, contains('setTexts'));
    expect((host.last('setTexts')!.args.single as Map)['start'], 'Start');
    expect(
      host.last('setStyle')!.args.first,
      'https://maps.example.org/tiles/styles/osm-bright/style.json',
    );
    await waitFor(() => host.named('registerImage').length >= 2);
    expect([
      for (final call in host.named('registerImage')) call.args.first,
    ], containsAll(['arrow-head', 'puck']));
    final home = host.last('showHome')!;
    final favourites = home.args[0] as List<CarPlace>;
    expect(favourites.single.id, 'home');
    expect(favourites.single.label, 'Voorthuizen');
    expect(home.args[2], isFalse, reason: 'no location yet');
  });

  test('dark mode: the night style, once it is there', () async {
    bridge.connected(
      CarSurface(
        width: 800,
        height: 480,
        density: 1,
        dark: true,
        platform: 'carplay',
      ),
    );
    await settle();
    // The regular style first; the night JSON needs a fetch that fails here.
    expect(host.last('setStyle')!.args[1], isFalse);
  });

  test('a recent place: location on, route preview, then the trip', () async {
    c.read(savedPlacesProvider.notifier).remember(target);
    bridge.connected(surface);
    await settle();
    final recents = host.last('showHome')!.args[1] as List<CarPlace>;
    expect(recents.single.id, 'recent:0');

    final chosen = bridge.placeChosen('recent:0');
    await Future<void>.delayed(Duration.zero);
    source.fixes.add(fix(route.points.first));
    await chosen;
    await settle();
    expect(bridge.screen, CarScreen.preview);
    final preview = host.last('showRoutePreview')!;
    expect(preview.args[0], 'Voorthuizen');
    final routes = preview.args[1] as List<CarRouteSummary>;
    expect(routes.single.meters, route.meters);
    expect(host.last('setRoutes'), isNotNull);
    expect(host.last('fitBounds'), isNotNull);
    expect(valhalla.requests.single.points.last, target.point);

    await bridge.startTrip();
    await settle();
    expect(bridge.screen, CarScreen.navigating);
    expect(c.read(navigationProvider), isNotNull);
    final trip = host.last('startNavigation')!.args.single as CarTrip;
    expect(trip.destinationLabel, 'Voorthuizen');
    expect(trip.remainingMeters, closeTo(route.meters, 1));
    // The first maneuver with its icon.
    await waitFor(() => host.last('updateManeuver') != null);
    final update = host.last('updateManeuver')!;
    final next = update.args[0] as CarManeuver;
    expect(next.instruction, route.maneuvers[1].instruction);
    expect([
      for (final call in host.named('registerImage')) call.args.first,
    ], contains(next.iconKey));
  });

  test(
    'driving: position and camera per fix, maneuver only on a change',
    () async {
      await locate();
      bridge.connected(surface);
      await settle();
      c.read(plannerProvider.notifier).showPlace(target);
      c.read(plannerProvider.notifier).startRoute();
      await settle();
      await bridge.startTrip();
      await settle();
      final before = host.named('updateManeuver').length;
      final positions = host.named('setPosition').length;
      final points = along(route.points, 20);
      for (final point in points.take(5)) {
        await driveTo(point);
      }
      expect(host.named('setPosition').length, positions + 5);
      expect(host.named('followCamera').length, greaterThanOrEqualTo(5));
      final camera = host.last('followCamera')!.args.single as CarCamera;
      expect(camera.tilt, 50);
      expect(camera.zoom, closeTo(16.2, 0.01), reason: '13 m/s');
      // 100 m in five fixes: the rounded distance changed at most a few times,
      // not five.
      final updates = host.named('updateManeuver').length - before;
      expect(updates, lessThan(5));
      expect(host.last('setDriven'), isNotNull);
      // A grey line up to the position on the route.
      final driven =
          jsonDecode(host.last('setDriven')!.args.single as String) as Map;
      expect((driven['features'] as List), hasLength(1));
    },
  );

  test('the driver moved the map: following stops until re-centre', () async {
    await locate();
    bridge.connected(surface);
    await settle();
    bridge.userMovedMap();
    final cameras = host.named('followCamera').length;
    await driveTo(route.points[1]);
    expect(host.named('followCamera').length, cameras);
    expect(host.last('setFollowing')!.args.single, isFalse);
    bridge.recenter();
    await settle();
    expect(host.named('followCamera').length, cameras + 1);
  });

  test('search: Photon near you, and a result is a destination', () async {
    await locate();
    bridge.connected(surface);
    final found = await bridge.search('Voorthuizen');
    expect(photon.searched, ['Voorthuizen']);
    expect(found.single.id, 'search:0');
    await bridge.placeChosen('search:0');
    await settle();
    expect(bridge.screen, CarScreen.preview);
    expect(c.read(plannerProvider).points.last.place?.label, 'Voorthuizen');
  });

  test(
    'a navigation intent with a search text goes straight to the preview',
    () async {
      await locate();
      bridge.connected(surface);
      await bridge.navigateTo(null, null, null, 'Voorthuizen');
      await settle();
      expect(bridge.screen, CarScreen.preview);
      expect(host.last('showRoutePreview'), isNotNull);
    },
  );

  test('stop: back to the home screen', () async {
    await locate();
    bridge.connected(surface);
    c.read(plannerProvider.notifier).showPlace(target);
    c.read(plannerProvider.notifier).startRoute();
    await settle();
    await bridge.startTrip();
    await settle();
    bridge.stopTrip();
    await settle();
    expect(c.read(navigationProvider), isNull);
    expect(host.names.last, 'setArrow');
    expect(host.names, contains('endNavigation'));
    expect(bridge.screen, CarScreen.home);
  });

  test('the test drive switches to the simulation', () async {
    await locate();
    bridge.connected(surface);
    c.read(plannerProvider.notifier).showPlace(target);
    c.read(plannerProvider.notifier).startRoute();
    await settle();
    await bridge.startTrip();
    await settle();
    bridge.autoDriveEnabled();
    expect(c.read(locationSourceProvider), isA<SimulationSource>());
  });

  test('disconnected: nothing to the car, navigation goes on', () async {
    await locate();
    bridge.connected(surface);
    c.read(plannerProvider.notifier).showPlace(target);
    c.read(plannerProvider.notifier).startRoute();
    await settle();
    await bridge.startTrip();
    await settle();
    bridge.disconnected();
    final count = host.calls.length;
    await driveTo(route.points[1]);
    expect(host.calls.length, count);
    expect(c.read(navigationProvider), isNotNull);
    // Plugged in again mid-trip: from scratch.
    bridge.connected(surface);
    await settle();
    expect(host.names.skip(count), contains('startNavigation'));
  });

  test('a faster route is an alert; accepting takes it', () async {
    await locate();
    bridge.connected(surface);
    c.read(plannerProvider.notifier).showPlace(target);
    c.read(plannerProvider.notifier).startRoute();
    await settle();
    await bridge.startTrip();
    await settle();
    for (final point in along(route.points, 20).take(10)) {
      await driveTo(point);
    }
    // A "different" route: the same shape, 500 m shorter, 500 s faster.
    valhalla.response = RouteOption(
      meters: route.meters - 500,
      seconds: route.seconds,
      points: route.points,
      maneuvers: route.maneuvers,
      elevations: const [],
      elevationInterval: 30,
      hasToll: false,
      hasFerry: false,
    );
    valhalla.time = (line) =>
        meters(line.first, route.points.first) < 1 ? 700 : 1200;
    await c.read(navigationProvider.notifier).searchFaster();
    await settle();
    expect(c.read(navigationProvider)!.suggestion, isNotNull);
    final alert = host.last('showAlert')!.args.single as CarAlert;
    expect(alert.id, 'faster');
    bridge.alertAnswered('faster', true);
    await settle();
    expect(c.read(navigationProvider)!.suggestion, isNull);
  });

  test('a speed camera ahead: its sign next to the limit', () async {
    final camera = along(route.points, 20)[40];
    c.dispose();
    c = ProviderContainer(
      overrides: [
        locationSourceProvider.overrideWithBuild((_, _) => source),
        voiceProvider.overrideWithValue(FakeVoice()),
        valhallaProvider.overrideWithValue(valhalla),
        photonProvider.overrideWithValue(photon),
        appConfigProvider.overrideWithValue(
          AppConfig.fromServer('https://maps.example.org'),
        ),
        carHostProvider.overrideWithValue(host),
        enforcementProvider.overrideWithValue(
          AsyncData({
            'type': 'FeatureCollection',
            'features': [
              {
                'type': 'Feature',
                'properties': {'kind': 'speed_camera'},
                'geometry': {
                  'type': 'Point',
                  'coordinates': [camera.longitude, camera.latitude],
                },
              },
            ],
          }),
        ),
      ],
    );
    addTearDown(c.dispose);
    bridge = c.read(carBridgeProvider);
    await locate();
    bridge.connected(surface);
    c.read(plannerProvider.notifier).showPlace(target);
    c.read(plannerProvider.notifier).startRoute();
    await settle();
    await bridge.startTrip();
    await settle();
    await driveTo(along(route.points, 20)[1]);
    await waitFor(
      () =>
          (host.last('updateManeuver')?.args[2] as CarSpeed?)?.cameraIconKey !=
          null,
    );
    final speed = host.last('updateManeuver')!.args[2] as CarSpeed;
    expect(speed.cameraIconKey, 'camera-speedCamera');
    expect(speed.cameraText, '800 m');
    expect(speed.cameraOver, isFalse);
    expect([
      for (final call in host.named('registerImage')) call.args.first,
    ], contains('camera-speedCamera'));
  });
}
