import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/models/place.dart';
import 'package:homemaps/providers/location.dart';
import 'package:homemaps/providers/planner.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'helpers/fake_source.dart';

Place place(String label, double lat) =>
    Place(label: label, point: LatLng(lat, 5));

void main() {
  late ProviderContainer container;
  late PlannerNotifier planner;
  PlannerState state() => container.read(plannerProvider);
  List<String?> names() => [for (final p in state().points) p.place?.label];

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    planner = container.read(plannerProvider.notifier);
  });

  test('replacing a moving place does not bring it back into view', () {
    planner.showPlace(place('Partner', 52.09));
    planner.replacePlace(place('Partner', 52.10));
    expect(state().found?.point, const LatLng(52.10, 5));
    expect(state().viewVersion, 1);
  });

  test('search first: choosing a place does not open a route yet', () {
    planner.showPlace(place('Dom', 52.09));
    expect(state().routeMode, isFalse);
    expect(state().found?.label, 'Dom');
    expect(state().viewVersion, 1);

    planner.startRoute();
    expect(state().routeMode, isTrue);
    expect(names(), [null, 'Dom']);

    planner.toSearch();
    expect(state().routeMode, isFalse);
    expect(state().found?.label, 'Dom');
    expect(names(), [null, null]);
  });

  test('clearing goes back to an empty search screen', () {
    planner.showPlace(place('Dom', 52.09));
    planner.startRoute();
    planner.setFrom(place('A', 52.1));

    planner.clear();
    expect(state().routeMode, isFalse);
    expect(state().found, isNull);
    expect(names(), [null, null]);
    expect(state().routes.value, isEmpty);
  });

  test('choosing a route in the list brings it back into view', () {
    planner.setFrom(place('A', 52.1), moveView: false);
    final before = state().viewVersion;
    planner.choose(1, moveView: true);
    expect(state().chosen, 1);
    expect(state().viewVersion, before + 1);
    // Tapped on the map: the view stays.
    planner.choose(0);
    expect(state().chosen, 0);
    expect(state().viewVersion, before + 1);
  });

  test('right mouse button goes straight to the route screen', () {
    planner.setFrom(place('A', 52.1), moveView: false);
    expect(state().routeMode, isTrue);
    expect(state().viewVersion, 0);
    planner.setTo(place('B', 52.2));
    expect(names(), ['A', 'B']);
  });

  test('reordering keeps the id with the place', () {
    planner.setFrom(place('A', 52.1));
    planner.addVia(place('B', 52.2));
    planner.setTo(place('C', 52.3));
    final idOfC = state().points.last.id;

    planner.reorder(2, 0); // C to the front
    expect(names(), ['C', 'A', 'B']);
    expect(state().points.first.id, idOfC);

    planner.reorder(0, 1); // C one place down
    expect(names(), ['A', 'C', 'B']);

    planner.swap();
    expect(names(), ['B', 'C', 'A']);
  });

  test('removing: a via disappears, from and to become empty', () {
    planner.setFrom(place('A', 52.1));
    planner.addVia(place('B', 52.2));
    planner.remove(1);
    expect(names(), ['A', null]);
    planner.remove(0);
    expect(names(), [null, null]);
  });

  test('renaming changes the name, not the order or the ids', () {
    planner.setFrom(Place.fromPoint(const LatLng(52.1, 5)));
    final id = state().points.first.id;
    planner.rename(0, place('Domplein 1', 52.1));
    expect(names(), ['Domplein 1', null]);
    expect(state().points.first.id, id);
  });

  test(
    'with your location on a new route departs from "My location"',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final source = FakeSource(PermissionAnswer.yes);
      final withLocation = ProviderContainer(
        overrides: [locationSourceProvider.overrideWithBuild((_, _) => source)],
      );
      addTearDown(withLocation.dispose);
      final wait = withLocation.read(locationProvider.notifier).turnOn();
      await Future<void>.delayed(Duration.zero);
      source.fixes.add(
        LocationFix(point: const LatLng(52.19, 5.7), time: DateTime(2026)),
      );
      await wait;

      final p = withLocation.read(plannerProvider.notifier);
      p.showPlace(place('Dom', 52.09));
      p.startRoute();
      final points = withLocation.read(plannerProvider).points;
      expect(points.first.place?.myLocation, isTrue);
      expect(points.first.place?.point, const LatLng(52.19, 5.7));
      expect(points.last.place?.label, 'Dom');

      // If you searched "My location" itself, that is the destination and from stays empty.
      p.toSearch();
      p.showPlace(Place.here(const LatLng(52.19, 5.7)));
      p.startRoute();
      expect(withLocation.read(plannerProvider).points.first.place, isNull);
    },
  );

  group('an empty from becomes "My location"', () {
    late FakeSource source;
    late ProviderContainer c;
    late PlannerNotifier p;
    List<Waypoint> points() => c.read(plannerProvider).points;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      source = FakeSource(PermissionAnswer.yes);
      c = ProviderContainer(
        overrides: [locationSourceProvider.overrideWithBuild((_, _) => source)],
      );
      addTearDown(c.dispose);
      p = c.read(plannerProvider.notifier);
    });

    Future<void> locate() async {
      final wait = c.read(locationProvider.notifier).turnOn();
      await Future<void>.delayed(Duration.zero);
      source.fixes.add(
        LocationFix(point: const LatLng(52.19, 5.7), time: DateTime(2026)),
      );
      await wait;
      await Future<void>.delayed(Duration.zero);
    }

    test('when only the destination is chosen', () async {
      await locate();
      p.setTo(place('Dom', 52.09), moveView: false);
      expect(points().first.place?.myLocation, isTrue);
      expect(points().last.place?.label, 'Dom');
    });

    test('not over a from you chose, nor for a via', () async {
      await locate();
      p.setFrom(place('A', 52.1));
      p.setTo(place('Dom', 52.09));
      expect(points().first.place?.label, 'A');

      p.remove(0);
      p.addVia(place('V', 52.15));
      expect(points().first.place, isNull);
    });

    test('once the first fix arrives after the route started', () async {
      p.showPlace(place('Dom', 52.09));
      p.startRoute();
      expect(points().first.place, isNull);
      await locate();
      expect(points().first.place?.myLocation, isTrue);
      expect(points().first.place?.point, const LatLng(52.19, 5.7));
    });

    test('not without a destination', () async {
      p.setFrom(place('A', 52.1));
      p.remove(0);
      await locate();
      expect(points().first.place, isNull);
    });
  });
}
