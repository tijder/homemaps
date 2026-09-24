import 'dart:async';

import 'package:homemaps/providers/location.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// A location source without GPS: the test decides the permission and the fixes.
class FakeSource implements LocationFixSource {
  FakeSource(this.response);

  PermissionAnswer response;
  int requested = 0;
  final fixes = StreamController<LocationFix>.broadcast();
  bool? lastAccurate;
  ({String title, String text})? lastNotification;

  @override
  Future<PermissionAnswer> check() async => response == PermissionAnswer.yes
      ? PermissionAnswer.yes
      : PermissionAnswer.no;

  @override
  Future<PermissionAnswer> ask() async {
    requested++;
    return response;
  }

  @override
  Stream<LocationFix> follow({
    required bool accurate,
    ({String title, String text})? notification,
  }) {
    lastAccurate = accurate;
    lastNotification = notification;
    return fixes.stream;
  }
}

LocationFix fix(double lat) =>
    LocationFix(point: LatLng(lat, 5.0), time: DateTime(2026, 9, 22));
