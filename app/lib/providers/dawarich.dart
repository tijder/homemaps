import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dawarich.dart';
import '../models/location_sharing.dart';
import '../services/dawarich_service.dart';
import 'services.dart';
import 'settings.dart';
import 'location_sharing.dart';

/// Dawarich's API key; not in the regular storage.
final dawarichSecretProvider = Provider<SecretStore>(
  (ref) => const SecureSecretStore('dawarichApiKey'),
);

final dawarichServiceProvider = Provider<DawarichService>(
  (ref) => DawarichService(ref.watch(dioProvider)),
);

/// The address that sharing while navigating goes to.
String dawarichPointsUrl(String server) => '$server/api/v1/points';

/// Do the general sharing settings point to this Dawarich account?
bool sharesViaDawarich(ShareSettings share, DawarichAccount? account) =>
    account != null &&
    share.template == ShareTemplate.dawarich &&
    share.url == dawarichPointsUrl(account.server);

/// The signed-in Dawarich account, or null.
class DawarichNotifier extends Notifier<DawarichAccount?> {
  static const _key = 'dawarich';
  static const _previousKey = 'dawarichPreviousServer';

  /// The server from last time, so it doesn't have to be typed again after
  /// signing out.
  String? get previousServer =>
      ref.read(settingsBoxProvider)?.get(_previousKey) as String? ?? _previous;
  String? _previous;

  String? _api;

  /// Done once the key has been read from secure storage.
  late Future<void> loaded;

  /// The API key, once [loaded] is done.
  String? get key => _api;

  @override
  DawarichAccount? build() {
    final account = DawarichAccount.fromMap(
      ref.watch(settingsBoxProvider)?.get(_key),
    );
    loaded = account == null ? Future.value() : _loadKey();
    return account;
  }

  Future<void> _loadKey() async {
    try {
      _api = await ref.read(dawarichSecretProvider).read();
    } on Object catch (error) {
      debugPrint('Could not read the Dawarich key: $error');
    }
  }

  Future<void> _save(DawarichAccount? account) async {
    state = account;
    final box = ref.read(settingsBoxProvider);
    if (account != null) {
      _previous = account.server;
      await box?.put(_previousKey, account.server);
    }
    await (account == null
        ? box?.delete(_key)
        : box?.put(_key, account.toMap()));
  }

  /// After signing in: store the key, and ask whether family is possible.
  Future<void> _signedIn(String key, DawarichAccount account) async {
    var fullAccount = account;
    try {
      final me = await ref
          .read(dawarichServiceProvider)
          .checkKey(account.server, key);
      fullAccount = account.copyWith(family: me.family);
    } on DawarichError {
      // Then just assume it is; family() will say otherwise.
    }
    _api = key;
    await ref.read(dawarichSecretProvider).write(key);
    await _save(fullAccount);
  }

  /// With email and password. Returns [DawarichTwoFactor] if a code is still
  /// needed; then [confirm].
  Future<DawarichLogin> signIn(
    String server,
    String email,
    String password,
  ) async {
    final outcome = await ref
        .read(dawarichServiceProvider)
        .login(server, email.trim(), password);
    if (outcome case DawarichSignedIn(:final key, :final account)) {
      await _signedIn(key, account);
    }
    return outcome;
  }

  /// The two-factor authentication code.
  Future<void> confirm(String server, String token, String code) async {
    final outcome = await ref
        .read(dawarichServiceProvider)
        .otp(server, token, code);
    await _signedIn(outcome.key, outcome.account);
  }

  /// With an API key from Dawarich (Settings, API key).
  Future<void> withKey(String server, String key) async {
    final trimmed = key.trim();
    final account = await ref
        .read(dawarichServiceProvider)
        .checkKey(server, trimmed);
    _api = trimmed;
    await ref.read(dawarichSecretProvider).write(trimmed);
    await _save(account);
  }

  /// Sign out; sharing to this account while navigating stops too.
  Future<void> signOut() async {
    final share = ref.read(shareSettingsProvider);
    if (sharesViaDawarich(share, state)) {
      await ref.read(shareSettingsProvider.notifier).loaded;
      await ref
          .read(shareSettingsProvider.notifier)
          .modify(
            ref
                .read(shareSettingsProvider)
                .copyWith(enabled: false, secret: ''),
          );
    }
    _api = null;
    await ref.read(dawarichSecretProvider).write('');
    await _save(null);
  }

  Future<void> setShowFamily(bool enabled) async {
    final account = state;
    if (account != null) await _save(account.copyWith(showFamily: enabled));
  }

  /// Sharing while navigating: fills the general sharing settings with this
  /// account, or turns them off.
  Future<void> setShareEnRoute(bool enabled) async {
    final account = state;
    await loaded;
    final key = _api;
    final notifier = ref.read(shareSettingsProvider.notifier);
    await notifier.loaded;
    final share = ref.read(shareSettingsProvider);
    if (!enabled) {
      if (share.enabled) await notifier.modify(share.copyWith(enabled: false));
      return;
    }
    if (account == null || key == null) return;
    await notifier.modify(
      share
          .withTemplate(ShareTemplate.dawarich)
          .copyWith(
            enabled: true,
            url: dawarichPointsUrl(account.server),
            auth: ShareAuth.bearer,
            secret: key,
          ),
    );
  }
}

final dawarichProvider = NotifierProvider<DawarichNotifier, DawarichAccount?>(
  DawarichNotifier.new,
);

/// Does the connection with the signed-in account work? Dawarich's version,
/// or a [DawarichError]: [DawarichErrorKind.auth] if the key is no longer
/// valid. Null if you are not signed in.
final dawarichConnectionProvider =
    FutureProvider.autoDispose<({String? version})?>(
      (ref) async {
        final account = ref.watch(dawarichProvider);
        if (account == null) return null;
        final notifier = ref.read(dawarichProvider.notifier);
        await notifier.loaded;
        final key = notifier.key;
        if (key == null) {
          throw const DawarichError(DawarichErrorKind.auth);
        }
        return ref.read(dawarichServiceProvider).check(account.server, key);
      },
      // Not again by itself: an expired key doesn't get any better, and for
      // "unreachable" there is the button.
      retry: (_, _) => null,
    );

/// Your place in the family; null if you are not signed in. A
/// [DawarichError] with [DawarichErrorKind.noFamily] if you are not in a
/// family.
class FamilyNotifier extends AsyncNotifier<FamilyStatus?> {
  @override
  Future<FamilyStatus?> build() async {
    final account = ref.watch(dawarichProvider);
    if (account == null) return null;
    final notifier = ref.read(dawarichProvider.notifier);
    await notifier.loaded;
    final key = notifier.key;
    if (key == null) return null;
    return ref.read(dawarichServiceProvider).family(account.server, key);
  }

  /// Share your location with the family: on (for [duration]) or off.
  Future<void> setSharing(bool enabled, {ShareDuration? duration}) async {
    final account = ref.read(dawarichProvider);
    final key = ref.read(dawarichProvider.notifier).key;
    if (account == null || key == null) return;
    await ref
        .read(dawarichServiceProvider)
        .setSharing(account.server, key, enabled: enabled, duration: duration);
    ref.invalidateSelf();
    await future;
  }
}

final familyProvider = AsyncNotifierProvider<FamilyNotifier, FamilyStatus?>(
  FamilyNotifier.new,
);

/// How often the family's locations are fetched. Dawarich has no live channel
/// for an API key.
const familyInterval = Duration(seconds: 30);

/// This often when you follow a family member.
const familyIntervalFollowing = Duration(seconds: 5);

/// The family member the map follows (their `user_id`), or null.
class FollowedMemberNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void follow(int userId) => state = userId;

  void stop() => state = null;
}

final followedMemberProvider = NotifierProvider<FollowedMemberNotifier, int?>(
  FollowedMemberNotifier.new,
);

/// The family members who share their location, for the map; empty when that
/// is off. Only fetched while the app is in the foreground, and more often
/// when you follow someone. If it fails, the previous locations stay (they
/// turn grey by themselves).
class FamilyLocationsNotifier extends Notifier<List<FamilyLocation>> {
  bool _busy = false;

  @override
  List<FamilyLocation> build() {
    final account = ref.watch(dawarichProvider);
    if (account == null || !account.showFamily) return const [];
    Timer? tick;
    void plan(int? followed) {
      tick?.cancel();
      tick = Timer.periodic(
        followed == null ? familyInterval : familyIntervalFollowing,
        (_) => fetch(),
      );
    }

    plan(ref.read(followedMemberProvider));
    // Not watch: then the list starts empty again and the markers flicker.
    ref.listen(followedMemberProvider, (_, followed) {
      plan(followed);
      if (followed != null) fetch();
    });
    final lifecycle = AppLifecycleListener(onResume: fetch);
    ref.onDispose(() {
      tick?.cancel();
      lifecycle.dispose();
    });
    Future.microtask(fetch);
    return const [];
  }

  Future<void> fetch() async {
    if (_busy) return;
    _busy = true;
    try {
      await _fetch();
    } finally {
      _busy = false;
    }
  }

  Future<void> _fetch() async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final account = ref.read(dawarichProvider);
    if (account == null || !account.showFamily) return;
    final notifier = ref.read(dawarichProvider.notifier);
    await notifier.loaded;
    final key = notifier.key;
    if (key == null) return;
    try {
      final all = await ref
          .read(dawarichServiceProvider)
          .locations(account.server, key);
      // Signed out or turned off in the meantime: show nothing anymore.
      if (!ref.mounted) return;
      state = [
        for (final member in all)
          if (member.userId != account.userId && member.email != account.email)
            member,
      ];
    } on DawarichError catch (error) {
      debugPrint('Could not fetch the family: $error');
    }
  }
}

final familyLocationsProvider =
    NotifierProvider<FamilyLocationsNotifier, List<FamilyLocation>>(
      FamilyLocationsNotifier.new,
    );
