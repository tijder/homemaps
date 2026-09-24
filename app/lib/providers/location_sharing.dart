import 'dart:async';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/location_sharing.dart';
import '../models/profile.dart';
import '../services/location_sharer.dart';
import '../utils/distance.dart';
import 'services.dart';
import 'settings.dart';
import 'location.dart';

/// The password or token for the server; not in the regular storage.
abstract class SecretStore {
  Future<String?> read();
  Future<void> write(String secret);
}

class SecureSecretStore implements SecretStore {
  const SecureSecretStore([this._key = 'locationSharingSecret']);

  final String _key;
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String secret) => secret.isEmpty
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: secret);
}

/// In memory: for tests, and when there is no secure storage.
class MemorySecretStore implements SecretStore {
  String? secret;

  @override
  Future<String?> read() async => secret;

  @override
  Future<void> write(String secret) async => this.secret = secret;
}

final secretStoreProvider = Provider<SecretStore>(
  (ref) => const SecureSecretStore(),
);

class ShareSettingsNotifier extends Notifier<ShareSettings> {
  static const _key = 'locationSharing';

  /// Done once the secret has been read from secure storage.
  late Future<void> loaded;

  @override
  ShareSettings build() {
    final box = ref.watch(settingsBoxProvider);
    final saved = ShareSettings.fromMap(box?.get(_key));
    loaded = _loadSecret();
    return saved;
  }

  Future<void> _loadSecret() async {
    try {
      final secret = await ref.read(secretStoreProvider).read();
      if (secret != null && secret.isNotEmpty) {
        state = state.copyWith(secret: secret);
      }
    } on Object catch (error) {
      debugPrint('Could not read the location sharing secret: $error');
    }
  }

  Future<void> modify(ShareSettings newValue) async {
    final old = state;
    state = newValue;
    await ref.read(settingsBoxProvider)?.put(_key, newValue.toMap());
    if (newValue.secret != old.secret) {
      await ref.read(secretStoreProvider).write(newValue.secret);
    }
  }
}

final shareSettingsProvider =
    NotifierProvider<ShareSettingsNotifier, ShareSettings>(
      ShareSettingsNotifier.new,
    );

/// Points that still have to go to the server, oldest first. With a Hive box
/// they survive a restart; without one (tests) they are kept in memory.
class ShareQueue {
  ShareQueue([this._box]);

  final Box<dynamic>? _box;
  final _memory = <SharedPoint>[];

  /// Keeping more makes no sense: then something is structurally wrong.
  static const maximum = 5000;

  int get length => _box?.length ?? _memory.length;

  Future<void> add(SharedPoint point) async {
    final box = _box;
    if (box == null) {
      _memory.add(point);
      if (_memory.length > maximum) {
        _memory.removeRange(0, _memory.length - maximum);
      }
      return;
    }
    await box.add(point.toMap());
    if (box.length > maximum) {
      await box.deleteAll(box.keys.take(box.length - maximum).toList());
    }
  }

  /// The oldest [count] points.
  List<SharedPoint> first(int count) {
    final box = _box;
    if (box == null) return _memory.take(count).toList();
    return [
      for (final raw in box.values.take(count))
        SharedPoint.fromMap(raw as Map<dynamic, dynamic>),
    ];
  }

  /// The oldest [count] points have arrived.
  Future<void> removeFirst(int count) async {
    final box = _box;
    if (box == null) {
      _memory.removeRange(0, min(count, _memory.length));
      return;
    }
    await box.deleteAll(box.keys.take(count).toList());
  }

  Future<void> clear() async {
    _memory.clear();
    await _box?.clear();
  }
}

/// Opens the queue's box; call before runApp (after [openSettings]).
Future<Box<dynamic>> openShareQueue() => Hive.openBox<dynamic>('shareQueue');

/// Overridden in main() with the opened box.
final shareQueueBoxProvider = Provider<Box<dynamic>?>((ref) => null);

final shareQueueProvider = Provider<ShareQueue>(
  (ref) => ShareQueue(ref.watch(shareQueueBoxProvider)),
);

/// The battery at the time of a point.
typedef BatteryReading = ({int? percent, String? currentState});

abstract class BatterySource {
  Future<BatteryReading> read();
}

/// Via battery_plus; asked at most once a minute, it doesn't change that fast.
/// If that fails (a browser without the Battery API), unknown.
class DeviceBattery implements BatterySource {
  final _battery = Battery();
  BatteryReading? _last;
  DateTime? _readAt;

  @override
  Future<BatteryReading> read() async {
    final now = DateTime.now();
    final last = _last;
    if (last != null && now.difference(_readAt!).inSeconds < 60) {
      return last;
    }
    BatteryReading value;
    try {
      final percent = await _battery.batteryLevel;
      final currentState = await _battery.batteryState;
      value = (
        percent: percent >= 0 && percent <= 100 ? percent : null,
        currentState: switch (currentState) {
          BatteryState.discharging => 'unplugged',
          BatteryState.charging ||
          BatteryState.connectedNotCharging => 'charging',
          BatteryState.full => 'full',
          BatteryState.unknown => null,
        },
      );
    } on Object {
      value = (percent: null, currentState: null);
    }
    _last = value;
    _readAt = now;
    return value;
  }
}

final batterySourceProvider = Provider<BatterySource>((ref) => DeviceBattery());

/// What Overland and Dawarich call the mode of transport.
String transportOf(Profile profile) => switch (profile) {
  Profile.car => 'driving',
  Profile.bike => 'cycling',
  Profile.walk => 'walking',
};

final shareSenderProvider = Provider<ShareSender>(
  (ref) => DioSender(ref.watch(dioProvider)),
);

/// How sharing is doing, for the screen.
@immutable
class ShareStatus {
  const ShareStatus({
    this.queued = 0,
    this.lastSent,
    this.error,
    this.stopped = false,
  });

  final int queued;
  final DateTime? lastSent;

  /// The last error ("HTTP 401", or that the server can't be reached).
  final String? error;

  /// After an error in the settings (4xx): only again after a change.
  final bool stopped;
}

/// Sends the position to the user's server while navigating, like Colota:
/// only when it is enabled and you are en route. What doesn't arrive stays in
/// the [ShareQueue] and goes later, in order.
class LocationSharer extends Notifier<ShareStatus> {
  SharedPoint? _previous;
  bool _busy = false;
  int _attempts = 0;
  Timer? _retry;

  /// Waiting times after a failed attempt: 30 s, 1 min, 2 min, then 5 min.
  static const _retryDelays = [30, 60, 120, 300];

  @override
  ShareStatus build() {
    ref.onDispose(() => _retry?.cancel());
    ref.listen(locationProvider.select((t) => t.fix), (_, fix) {
      if (fix != null) _onFix(fix);
    });
    // Done navigating: try one more time.
    ref.listen(enRouteProvider, (_, enRoute) {
      if (!enRoute) {
        _previous = null;
        empty();
      }
    });
    // Different settings: an earlier error no longer applies.
    ref.listen(shareSettingsProvider, (_, _) {
      _attempts = 0;
      _retry?.cancel();
      state = ShareStatus(
        queued: ref.read(shareQueueProvider).length,
        lastSent: state.lastSent,
      );
      empty();
    });
    final queue = ref.read(shareQueueProvider);
    // Left over from a previous time: send it now after all.
    if (queue.length > 0) Future.microtask(empty);
    return ShareStatus(queued: queue.length);
  }

  Future<void> _onFix(LocationFix fix) async {
    final settings = ref.read(shareSettingsProvider);
    if (!settings.enabled || !settings.complete || !ref.read(enRouteProvider)) {
      return;
    }
    // A fix more than a hundred meters wide says too little.
    if (fix.accuracy > 100) return;
    final tst = fix.time.millisecondsSinceEpoch ~/ 1000;
    final previous = _previous;
    if (previous != null &&
        tst - previous.tst < settings.interval &&
        meters(fix.point, _position(previous)) < settings.minDistance) {
      return;
    }
    // Right away, otherwise the next fix also gets through while waiting for
    // the battery.
    _previous = SharedPoint(
      lat: fix.point.latitude,
      lon: fix.point.longitude,
      tst: tst,
    );
    final battery = await ref.read(batterySourceProvider).read();
    final point = SharedPoint(
      lat: fix.point.latitude,
      lon: fix.point.longitude,
      tst: tst,
      acc: fix.accuracy,
      alt: fix.elevation,
      vel: fix.speed,
      bear: fix.heading,
      vac: fix.altitudeAccuracy,
      bearAcc: fix.headingAccuracy,
      batt: battery.percent,
      bs: battery.currentState,
      transport: transportOf(ref.read(settingsProvider).profile),
    );
    final queue = ref.read(shareQueueProvider);
    await queue.add(point);
    state = ShareStatus(
      queued: queue.length,
      lastSent: state.lastSent,
      error: state.error,
      stopped: state.stopped,
    );
    await empty();
  }

  /// Sends the queue, oldest first, until it is empty or something goes wrong.
  Future<void> empty() async {
    if (_busy || state.stopped || (_retry?.isActive ?? false)) return;
    await ref.read(shareSettingsProvider.notifier).loaded;
    final settings = ref.read(shareSettingsProvider);
    if (!settings.complete) return;
    final queue = ref.read(shareQueueProvider);
    final sender = ref.read(shareSenderProvider);
    _busy = true;
    try {
      while (queue.length > 0) {
        final points = queue.first(pointsPerRequest(settings));
        String? error;
        var status = 0;
        try {
          status = await sender.send(buildRequest(settings, points));
        } on Object catch (e) {
          error = _errorText(e);
        }
        if (status >= 200 && status < 300) {
          await queue.removeFirst(points.length);
          _attempts = 0;
          state = ShareStatus(queued: queue.length, lastSent: DateTime.now());
          continue;
        }
        error ??= 'HTTP $status';
        // A 4xx is the setting (address, key, field names): retrying doesn't
        // help. Except "timeout" and "too many requests".
        final settingsError =
            status >= 400 && status < 500 && status != 408 && status != 429;
        state = ShareStatus(
          queued: queue.length,
          lastSent: state.lastSent,
          error: error,
          stopped: settingsError,
        );
        if (!settingsError) {
          final wait = _retryDelays[min(_attempts, _retryDelays.length - 1)];
          _attempts++;
          _retry = Timer(Duration(seconds: wait), empty);
        }
        return;
      }
    } finally {
      _busy = false;
    }
  }

  /// "Test connection": one point, bypassing the queue. Returns the error, or
  /// null if it arrived.
  Future<String?> test(ShareSettings settings, SharedPoint point) async {
    try {
      final status = await ref
          .read(shareSenderProvider)
          .send(buildRequest(settings, [point]));
      return status >= 200 && status < 300 ? null : 'HTTP $status';
    } on Object catch (e) {
      return _errorText(e);
    }
  }

  Future<void> clearQueue() async {
    final queue = ref.read(shareQueueProvider);
    await queue.clear();
    _retry?.cancel();
    state = ShareStatus(lastSent: state.lastSent);
  }
}

/// Short and readable: Dio's own text is half a page.
String _errorText(Object error) => error is DioException
    ? (error.message ?? error.error?.toString() ?? error.type.name)
    : '$error';

LatLng _position(SharedPoint p) => LatLng(p.lat, p.lon);

final locationSharerProvider = NotifierProvider<LocationSharer, ShareStatus>(
  LocationSharer.new,
);
