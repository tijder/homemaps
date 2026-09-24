import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'settings.dart';

/// One position fix of the device.
@immutable
class LocationFix {
  const LocationFix({
    required this.point,
    required this.time,
    this.accuracy = 0,
    this.heading,
    this.speed,
    this.elevation,
    this.altitudeAccuracy,
    this.headingAccuracy,
  });

  final LatLng point;
  final DateTime time;

  /// Radius of the uncertainty, in meters.
  final double accuracy;

  /// Direction of travel in degrees (0 = north), or null if the device is
  /// stationary or doesn't know.
  final double? heading;

  /// In m/s, or null if unknown.
  final double? speed;

  /// Above sea level (m), or null if the device doesn't know.
  final double? elevation;

  /// In meters.
  final double? altitudeAccuracy;

  /// In degrees.
  final double? headingAccuracy;
}

enum LocationStatus {
  /// Not asked, or turned off by the user.
  off,

  /// Permission is being asked, or the first fix is in progress.
  searching,
  enabled,
  denied,

  /// Denied with "don't ask again": can only be undone in the settings.
  permanentlyDenied,

  /// The device's location services are off.
  serviceOff,

  /// Permission is there, but the device can't get a fix (indoors, or a
  /// computer without a location service). It keeps searching.
  notFound,
}

@immutable
class LocationState {
  const LocationState([this.status = LocationStatus.off, this.fix]);

  final LocationStatus status;

  /// The last fix; only when [status] is `enabled`.
  final LocationFix? fix;
}

enum PermissionAnswer { yes, no, never, serviceOff }

/// Where the fixes come from. Separate from the notifier so tests and the
/// navigation simulation can provide their own source.
abstract class LocationFixSource {
  /// Without asking: is there permission already?
  Future<PermissionAnswer> check();

  /// Asks the user if that is still possible.
  Future<PermissionAnswer> ask();

  /// [notification]: keep fetching alive with the screen off too: on Android
  /// with a persistent notification (foreground service), on iOS as background
  /// location. Null = foreground only.
  Stream<LocationFix> follow({
    required bool accurate,
    ({String title, String text})? notification,
  });
}

class GeolocatorSource implements LocationFixSource {
  const GeolocatorSource();

  static PermissionAnswer _translate(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always ||
        LocationPermission.whileInUse => PermissionAnswer.yes,
        LocationPermission.deniedForever => PermissionAnswer.never,
        _ => PermissionAnswer.no,
      };

  @override
  Future<PermissionAnswer> check() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return PermissionAnswer.serviceOff;
    }
    return _translate(await Geolocator.checkPermission());
  }

  @override
  Future<PermissionAnswer> ask() async {
    final now = await check();
    if (now != PermissionAnswer.no) return now;
    return _translate(await Geolocator.requestPermission());
  }

  @override
  Stream<LocationFix> follow({
    required bool accurate,
    ({String title, String text})? notification,
  }) {
    final settings = kIsWeb
        ? WebSettings(
            accuracy: LocationAccuracy.high,
            maximumAge: Duration.zero,
          )
        : defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: accurate ? 2 : 5,
            intervalDuration: const Duration(seconds: 1),
            foregroundNotificationConfig: notification == null
                ? null
                : ForegroundNotificationConfig(
                    notificationTitle: notification.title,
                    notificationText: notification.text,
                    enableWakeLock: true,
                    setOngoing: true,
                  ),
          )
        : defaultTargetPlatform == TargetPlatform.iOS
        // With a notification (navigation) it continues with the screen off
        // too, like the foreground service on Android; iOS then shows the blue
        // location indicator.
        ? AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: accurate ? 2 : 5,
            activityType: notification == null
                ? ActivityType.other
                : ActivityType.otherNavigation,
            pauseLocationUpdatesAutomatically: false,
            allowBackgroundLocationUpdates: notification != null,
            showBackgroundLocationIndicator: notification != null,
          )
        : LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: accurate ? 2 : 5,
          );
    return Geolocator.getPositionStream(locationSettings: settings).map(
      (p) => LocationFix(
        point: LatLng(p.latitude, p.longitude),
        time: p.timestamp,
        accuracy: p.accuracy,
        // When stationary a heading is noise; on the web it is often NaN.
        heading: p.speed > 1 && p.heading.isFinite && p.heading >= 0
            ? p.heading
            : null,
        speed: p.speed.isFinite && p.speed >= 0 ? p.speed : null,
        // Without an accuracy the altitude is a meaningless 0 (web).
        elevation: p.altitudeAccuracy > 0 && p.altitude.isFinite
            ? p.altitude
            : null,
        altitudeAccuracy: p.altitudeAccuracy > 0 ? p.altitudeAccuracy : null,
        headingAccuracy:
            p.speed > 1 && p.headingAccuracy.isFinite && p.headingAccuracy > 0
            ? p.headingAccuracy
            : null,
      ),
    );
  }
}

final locationSourceProvider = Provider<LocationFixSource>(
  (ref) => const GeolocatorSource(),
);

/// Your own location. Only on after a tap by the user, never by itself at
/// startup -- unless you had it on last time and the permission is still
/// there: then without asking again.
class LocationNotifier extends Notifier<LocationState> {
  StreamSubscription<LocationFix>? _stream;
  AppLifecycleListener? _lifecycle;

  /// During navigation: more accurate, and on Android in the background too.
  ({String title, String text})? _navigation;
  bool _navigating = false;

  /// Who is waiting for the first fix (see [firstFix]).
  final _waiters = <Completer<LocationFix?>>[];

  @override
  LocationState build() {
    ref.onDispose(() {
      _stream?.cancel();
      _lifecycle?.dispose();
      _report(null);
    });
    if (ref.read(settingsProvider).locationEnabled) {
      Future.microtask(_resume);
    }
    return const LocationState();
  }

  Future<void> _resume() async {
    final source = ref.read(locationSourceProvider);
    if (await source.check() == PermissionAnswer.yes) {
      state = const LocationState(LocationStatus.searching);
      _start();
    }
  }

  /// Asks for permission if needed and waits for the first fix (at most
  /// 20 s). Null if that fails; the reason is then in the state.
  Future<LocationFix?> turnOn() async {
    if (state.fix case final fix?) return fix;
    // Already (or still) searching: don't ask and start again, just wait.
    if (_stream != null) {
      state = const LocationState(LocationStatus.searching);
      return firstFix();
    }
    state = const LocationState(LocationStatus.searching);
    final response = await ref.read(locationSourceProvider).ask();
    if (response != PermissionAnswer.yes) {
      state = LocationState(switch (response) {
        PermissionAnswer.never => LocationStatus.permanentlyDenied,
        PermissionAnswer.serviceOff => LocationStatus.serviceOff,
        _ => LocationStatus.denied,
      });
      return null;
    }
    _save(true);
    _start();
    return firstFix();
  }

  void turnOff() {
    _stop();
    _save(false);
    state = const LocationState();
  }

  /// The current fix, or the next one if there isn't one yet.
  Future<LocationFix?> firstFix() async {
    if (state.fix case final fix?) return fix;
    if (state.status != LocationStatus.searching &&
        state.status != LocationStatus.notFound) {
      return null;
    }
    final done = Completer<LocationFix?>();
    _waiters.add(done);
    return done.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _waiters.remove(done);
        // Keeps searching, but now honestly says it isn't working yet.
        if (state.status == LocationStatus.searching) {
          state = const LocationState(LocationStatus.notFound);
        }
        return null;
      },
    );
  }

  void _report(LocationFix? fix) {
    for (final done in _waiters) {
      if (!done.isCompleted) done.complete(fix);
    }
    _waiters.clear();
  }

  /// Navigation on or off: restart the stream, with other settings.
  void navigation(({String title, String text})? notification) {
    _navigating = notification != null;
    _navigation = notification;
    if (_stream != null) {
      _stop();
      _start();
    }
  }

  void _start() {
    // Not in the foreground: stop, except during navigation. Back: continue.
    _lifecycle ??= AppLifecycleListener(
      onHide: () {
        if (!_navigating) _stop();
      },
      onShow: () {
        final busy =
            state.status == LocationStatus.enabled ||
            state.status == LocationStatus.notFound;
        if (busy && _stream == null) _start();
      },
    );
    _stream = ref
        .read(locationSourceProvider)
        .follow(accurate: _navigating, notification: _navigation)
        .listen(
          (fix) {
            state = LocationState(LocationStatus.enabled, fix);
            _report(fix);
          },
          onError: (Object error) {
            // No fix (yet): keep searching, the browser or the device retries
            // by itself.
            if (error is! PermissionDeniedException &&
                error is! LocationServiceDisabledException) {
              if (state.fix == null) {
                state = const LocationState(LocationStatus.notFound);
                _report(null);
              }
              return;
            }
            // Permission revoked along the way, or the service turned off.
            _stop();
            state = LocationState(
              error is LocationServiceDisabledException
                  ? LocationStatus.serviceOff
                  : LocationStatus.denied,
            );
            _report(null);
          },
        );
  }

  void _stop() {
    _stream?.cancel();
    _stream = null;
  }

  void _save(bool enabled) {
    final settings = ref.read(settingsProvider);
    if (settings.locationEnabled != enabled) {
      ref
          .read(settingsProvider.notifier)
          .modify(settings.copyWith(locationEnabled: enabled));
    }
  }
}

final locationProvider = NotifierProvider<LocationNotifier, LocationState>(
  LocationNotifier.new,
);
