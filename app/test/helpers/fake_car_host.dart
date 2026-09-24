import 'dart:typed_data';

import 'package:homemaps/car/car_api.g.dart';

/// The car as the bridge sees it: remembers every call.
class FakeCarHost extends CarHostApi {
  /// (method name, arguments), in order.
  final calls = <({String name, List<Object?> args})>[];

  List<String> get names => [for (final c in calls) c.name];
  Iterable<({String name, List<Object?> args})> named(String name) =>
      calls.where((c) => c.name == name);
  ({String name, List<Object?> args})? last(String name) =>
      named(name).lastOrNull;

  void _record(String name, [List<Object?> args = const []]) =>
      calls.add((name: name, args: args));

  @override
  Future<void> ready() async => _record('ready');
  @override
  Future<void> setTexts(Map<String, String> texts) async =>
      _record('setTexts', [texts]);
  @override
  Future<void> setStyle(String style, bool isJson) async =>
      _record('setStyle', [style, isJson]);
  @override
  Future<void> registerImage(String key, Uint8List png, double scale) async =>
      _record('registerImage', [key, png, scale]);
  @override
  Future<void> setRoutes(String geoJson) async =>
      _record('setRoutes', [geoJson]);
  @override
  Future<void> setDriven(String geoJson) async =>
      _record('setDriven', [geoJson]);
  @override
  Future<void> setArrow(String geoJson) async => _record('setArrow', [geoJson]);
  @override
  Future<void> setPosition(CarPosition position) async =>
      _record('setPosition', [position]);
  @override
  Future<void> followCamera(CarCamera camera) async =>
      _record('followCamera', [camera]);
  @override
  Future<void> fitBounds(CarBounds bounds, double paddingPx) async =>
      _record('fitBounds', [bounds, paddingPx]);
  @override
  Future<void> setFollowing(bool following) async =>
      _record('setFollowing', [following]);
  @override
  Future<void> showHome(
    List<CarPlace> favourites,
    List<CarPlace> recents,
    bool locationOk,
  ) async => _record('showHome', [favourites, recents, locationOk]);
  @override
  Future<void> showRoutePreview(
    String destinationLabel,
    List<CarRouteSummary> routes,
    int chosen,
  ) async => _record('showRoutePreview', [destinationLabel, routes, chosen]);
  @override
  Future<void> showLoading(bool loading) async =>
      _record('showLoading', [loading]);
  @override
  Future<void> showMessage(String title, String text) async =>
      _record('showMessage', [title, text]);
  @override
  Future<void> startNavigation(CarTrip trip) async =>
      _record('startNavigation', [trip]);
  @override
  Future<void> updateManeuver(
    CarManeuver next,
    CarTrip trip,
    CarSpeed speed,
  ) async => _record('updateManeuver', [next, trip, speed]);
  @override
  Future<void> setRecalculating(bool recalculating) async =>
      _record('setRecalculating', [recalculating]);
  @override
  Future<void> showArrived(String destinationLabel) async =>
      _record('showArrived', [destinationLabel]);
  @override
  Future<void> endNavigation() async => _record('endNavigation');
  @override
  Future<void> setMuted(bool muted) async => _record('setMuted', [muted]);
  @override
  Future<void> showAlert(CarAlert alert) async => _record('showAlert', [alert]);
  @override
  Future<void> dismissAlert(String id) async => _record('dismissAlert', [id]);
}
