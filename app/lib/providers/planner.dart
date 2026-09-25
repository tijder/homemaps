import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/place.dart';
import '../models/route.dart';
import '../services/valhalla_service.dart';
import '../utils/planned_closures.dart';
import 'services.dart';
import 'settings.dart';
import 'location.dart';

/// One field of the route. The [id] stays with the field when the order
/// changes, so that dragging in the list and on the map mean the same point.
class Waypoint {
  const Waypoint(this.id, [this.place]);

  final int id;
  final Place? place;
}

class PlannerState {
  const PlannerState({
    this.routeMode = false,
    this.found,
    this.points = const [Waypoint(0), Waypoint(1)],
    this.routes = const AsyncData([]),
    this.chosen = 0,
    this.viewVersion = 0,
    this.departure,
  });

  /// False: the search screen (one search bar, possibly a found place).
  /// True: the route screen with from/via/to.
  final bool routeMode;

  /// The place chosen in the search screen.
  final Place? found;

  /// From, any intermediate points, to. Always at least two.
  final List<Waypoint> points;
  final AsyncValue<List<RouteOption>> routes;
  final int chosen;

  /// Goes up whenever the map has to bring the result into view: after a
  /// search it does, after dragging a point it doesn't.
  final int viewVersion;

  /// Leaving later: then Valhalla calculates for that time (without the
  /// current traffic) and the app warns about planned closures. Null = now.
  final DateTime? departure;

  bool get complete => points.every((p) => p.place != null);

  RouteOption? get chosenRoute {
    final list = routes.value;
    if (list == null || list.isEmpty) return null;
    return list[chosen.clamp(0, list.length - 1)];
  }

  PlannerState copyWith({
    bool? routeMode,
    Place? Function()? found,
    List<Waypoint>? points,
    AsyncValue<List<RouteOption>>? routes,
    int? chosen,
    int? viewVersion,
    DateTime? Function()? departure,
  }) => PlannerState(
    routeMode: routeMode ?? this.routeMode,
    found: found != null ? found() : this.found,
    points: points ?? this.points,
    routes: routes ?? this.routes,
    chosen: chosen ?? this.chosen,
    viewVersion: viewVersion ?? this.viewVersion,
    departure: departure != null ? departure() : this.departure,
  );
}

class PlannerNotifier extends Notifier<PlannerState> {
  CancelToken? _inFlight;
  int _nextId = 2;

  /// The language for the instructions; the screen sets it when building.
  String language = 'nl-NL';

  @override
  PlannerState build() {
    // A different mode of transport or option is a different route; a map
    // layer or the location isn't.
    ref.listen(
      settingsProvider.select(
        (s) => (
          s.profile,
          s.liveTraffic,
          s.avoidMotorways,
          s.avoidTolls,
          s.avoidFerries,
        ),
      ),
      (_, _) => _calculate(moveView: false),
    );
    // A route started before the first fix still departs from here once
    // there is one.
    ref.listen(locationProvider.select((l) => l.fix != null), (had, has) {
      if ((had ?? true) || !has || !state.routeMode) return;
      final points = _fromHere(state.points);
      if (identical(points, state.points)) return;
      state = state.copyWith(
        points: points,
        viewVersion: state.viewVersion + 1,
      );
      _calculate(moveView: true);
    });
    ref.onDispose(() => _inFlight?.cancel());
    return const PlannerState();
  }

  // ------------------------------------------------------------- search screen

  void showPlace(Place place) => state = state.copyWith(
    found: () => place,
    viewVersion: state.viewVersion + 1,
  );

  /// The same place with new data (a family member who moves), without
  /// bringing it into view again.
  void replacePlace(Place place) => state = state.copyWith(found: () => place);

  void closePlace() => state = state.copyWith(found: () => null);

  /// "Route" on the found place: it becomes the destination. If your location
  /// is on, you leave from there.
  void startRoute() {
    final target = state.found;
    final points = _fromHere([
      Waypoint(_nextId++),
      Waypoint(_nextId++, target),
    ]);
    final complete = points.first.place != null;
    state = PlannerState(
      routeMode: true,
      found: target,
      points: points,
      viewVersion: state.viewVersion + (complete ? 1 : 0),
    );
    if (complete) _calculate(moveView: true);
  }

  /// [points] with "My location" as from, if from is still empty, there is a
  /// destination and a location, and the destination isn't your location
  /// itself. Otherwise [points] itself.
  List<Waypoint> _fromHere(List<Waypoint> points) {
    final here = ref.read(locationProvider).fix;
    final to = points.last.place;
    if (here == null ||
        points.first.place != null ||
        to == null ||
        to.myLocation) {
      return points;
    }
    return [
      Waypoint(points.first.id, Place.here(here.point)),
      ...points.skip(1),
    ];
  }

  /// Back to the search screen; the route is gone, the found place stays.
  void toSearch() {
    _inFlight?.cancel();
    state = PlannerState(found: state.found, viewVersion: state.viewVersion);
  }

  /// After arrival: back to an empty search screen, without a route or found
  /// place.
  void clear() {
    _inFlight?.cancel();
    state = PlannerState(viewVersion: state.viewVersion);
  }

  // -------------------------------------------------------------- route screen

  /// [moveView]: bring the result into view. Not when dragging on the map --
  /// then the map jumps away from under your hand.
  void setPoint(int index, Place? place, {bool moveView = true}) {
    var points = [...state.points];
    points[index] = Waypoint(points[index].id, place);
    // Choosing where to go is enough when your location is known.
    if (index == points.length - 1) points = _fromHere(points);
    state = state.copyWith(
      routeMode: true,
      points: points,
      viewVersion: moveView ? state.viewVersion + 1 : null,
    );
    _calculate(moveView: moveView);
  }

  /// Only update a point's name (the address of a tapped point); the place is
  /// the same, so no new route is needed.
  void rename(int index, Place place) {
    final points = [...state.points];
    points[index] = Waypoint(points[index].id, place);
    state = state.copyWith(points: points);
  }

  void setFrom(Place place, {bool moveView = true}) =>
      setPoint(0, place, moveView: moveView);

  void setTo(Place place, {bool moveView = true}) =>
      setPoint(state.points.length - 1, place, moveView: moveView);

  void addVia([Place? place]) {
    final points = [...state.points]
      ..insert(state.points.length - 1, Waypoint(_nextId++, place));
    state = state.copyWith(routeMode: true, points: points);
    if (place != null) _calculate(moveView: false);
  }

  void remove(int index) {
    final points = [...state.points];
    if (points.length > 2) {
      points.removeAt(index);
    } else {
      points[index] = Waypoint(points[index].id);
    }
    state = state.copyWith(points: points);
    _calculate(moveView: false);
  }

  /// [to] is the position in the list after removing [from] (that is how
  /// ReorderableListView.onReorderItem delivers it).
  void reorder(int from, int to) {
    final points = [...state.points];
    points.insert(to, points.removeAt(from));
    // A different order is a whole different route: bring it into view again.
    state = state.copyWith(points: points, viewVersion: state.viewVersion + 1);
    _calculate(moveView: true);
  }

  void swap() {
    state = state.copyWith(
      points: state.points.reversed.toList(),
      viewVersion: state.viewVersion + 1,
    );
    _calculate(moveView: true);
  }

  /// [moveView]: bring the routes fully into view again (a choice in the
  /// list). Not when tapping a route on the map: you are already looking there.
  void choose(int index, {bool moveView = false}) => state = state.copyWith(
    chosen: index,
    viewVersion: moveView ? state.viewVersion + 1 : null,
  );

  /// Null = leave now.
  void setDeparture(DateTime? departure) {
    state = state.copyWith(departure: () => departure);
    _calculate(moveView: false);
  }

  Future<void> _calculate({required bool moveView}) async {
    _inFlight?.cancel();
    final valhalla = ref.read(valhallaProvider);
    if (!state.complete || valhalla == null) {
      state = state.copyWith(routes: const AsyncData([]), chosen: 0);
      return;
    }
    final cancel = _inFlight = CancelToken();
    final settings = ref.read(settingsProvider);
    state = state.copyWith(routes: const AsyncLoading(), chosen: 0);
    try {
      final routes = await valhalla.route(
        [for (final point in state.points) point.place!.point],
        settings.profile,
        language: language,
        liveTraffic: settings.liveTraffic,
        avoidMotorways: settings.avoidMotorways,
        avoidTolls: settings.avoidTolls,
        avoidFerries: settings.avoidFerries,
        departure: state.departure,
        cancel: cancel,
      );
      if (cancel.isCancelled) return;
      state = state.copyWith(
        routes: AsyncData(routes),
        // Once more: only now is there a route to bring into view.
        viewVersion: moveView ? state.viewVersion + 1 : null,
      );
    } on DioException catch (error) {
      // Cancelled by a newer request: that one writes the outcome itself.
      if (!CancelToken.isCancel(error)) {
        state = state.copyWith(routes: AsyncError(error, StackTrace.current));
      }
    } on RouteError catch (error, stackTrace) {
      if (!cancel.isCancelled) {
        state = state.copyWith(routes: AsyncError(error, stackTrace));
      }
    }
  }
}

final plannerProvider = NotifierProvider<PlannerNotifier, PlannerState>(
  PlannerNotifier.new,
);

/// Per route (in the order of [PlannerState.routes]) the planned closures on
/// it if you leave later; null if you leave now or the planning isn't there
/// (yet).
final closuresOnRoutesProvider = Provider<List<List<ClosureOnRoute>>?>((ref) {
  final departure = ref.watch(plannerProvider.select((p) => p.departure));
  if (departure == null) return null;
  final routes = ref.watch(plannerProvider.select((p) => p.routes.value));
  final layer = ref.watch(plannedProvider).value;
  if (routes == null || layer == null) return null;
  return [for (final route in routes) closuresOnRoute(route, layer, departure)];
});
