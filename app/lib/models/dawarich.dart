import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// The Dawarich account that is logged in. The API key isn't in regular
/// storage, see `dawarichSecretProvider`.
@immutable
class DawarichAccount {
  const DawarichAccount({
    required this.server,
    required this.email,
    this.userId,
    this.family = true,
    this.showFamily = false,
  });

  /// Without a trailing `/`, for example `https://dawarich.example`.
  final String server;
  final String email;

  /// Null after logging in with a pasted key: `/users/me` doesn't return it.
  final int? userId;

  /// Can this account use family (`features.family`)? On Dawarich Cloud only
  /// with the Family plan.
  final bool family;

  /// Show family members on the map.
  final bool showFamily;

  DawarichAccount copyWith({bool? family, bool? showFamily}) => DawarichAccount(
    server: server,
    email: email,
    userId: userId,
    family: family ?? this.family,
    showFamily: showFamily ?? this.showFamily,
  );

  Map<String, Object?> toMap() => {
    'server': server,
    'email': email,
    'userId': userId,
    'family': family,
    'showFamily': showFamily,
  };

  static DawarichAccount? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final server = raw['server'];
    if (server is! String || server.isEmpty) return null;
    return DawarichAccount(
      server: server,
      email: raw['email'] as String? ?? '',
      userId: (raw['userId'] as num?)?.toInt(),
      family: raw['family'] != false,
      showFamily: raw['showFamily'] == true,
    );
  }
}

/// How long you share your location with the family; the values are
/// Dawarich's.
enum ShareDuration {
  hour1('1h'),
  hour6('6h'),
  hour12('12h'),
  hour24('24h'),
  always('permanent');

  const ShareDuration(this.value);

  final String value;

  static ShareDuration? from(Object? value) =>
      values.where((d) => d.value == value).firstOrNull;
}

/// Your place in the family, from `/api/v1/families/mine`.
@immutable
class FamilyStatus {
  const FamilyStatus({
    required this.label,
    required this.sharingEnabled,
    this.duration,
    this.expiresAt,
    this.members = const [],
  });

  final String label;

  /// As Dawarich says it; that stays true after [expiresAt] has passed. See
  /// [isSharing].
  final bool sharingEnabled;

  /// Null when Dawarich gave a custom number of hours.
  final ShareDuration? duration;

  /// Null for "always".
  final DateTime? expiresAt;

  /// The email addresses of the others in the family.
  final List<String> members;

  /// Whether you share at [now]: on, and the time not yet past.
  bool isSharing(DateTime now) =>
      sharingEnabled && (expiresAt == null || now.isBefore(expiresAt!));

  factory FamilyStatus.fromJson(Map<String, dynamic> json) {
    final sharing = (json['me'] as Map?)?['sharing'] as Map? ?? const {};
    final myId = (json['me'] as Map?)?['user_id'];
    return FamilyStatus(
      label: (json['family'] as Map?)?['name'] as String? ?? '',
      sharingEnabled: sharing['enabled'] == true,
      duration: ShareDuration.from(sharing['duration']),
      expiresAt: DateTime.tryParse('${sharing['expires_at']}')?.toLocal(),
      members: [
        for (final member in (json['members'] as List? ?? const []))
          if (member is Map && member['user_id'] != myId) '${member['email']}',
      ],
    );
  }
}

/// The last position of a family member who shares their location.
@immutable
class FamilyLocation {
  const FamilyLocation({
    required this.userId,
    required this.email,
    required this.initial,
    required this.point,
    required this.time,
    this.battery,
  });

  final int userId;
  final String email;
  final String initial;
  final LatLng point;
  final DateTime time;

  /// Percent, if Dawarich knows it.
  final int? battery;

  /// One row from `/api/v1/families/locations`; null if something is missing.
  static FamilyLocation? fromJson(Map<String, dynamic> json) {
    final id = json['user_id'], lat = json['latitude'], lon = json['longitude'];
    if (id is! num) return null;
    final latitude = lat is num ? lat.toDouble() : double.tryParse('$lat');
    final longitude = lon is num ? lon.toDouble() : double.tryParse('$lon');
    if (latitude == null || longitude == null) return null;
    final ts = json['timestamp'];
    final time = ts is num
        ? DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000)
        : DateTime.tryParse('$ts')?.toLocal() ?? DateTime.now();
    final email = json['email'] as String? ?? '';
    final initial = json['email_initial'] as String? ?? '';
    return FamilyLocation(
      userId: id.toInt(),
      email: email,
      initial:
          (initial.isNotEmpty
                  ? initial
                  : email.isNotEmpty
                  ? email.substring(0, 1)
                  : '?')
              .toUpperCase(),
      point: LatLng(latitude, longitude),
      time: time,
      battery: (json['battery'] as num?)?.round(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FamilyLocation &&
      other.userId == userId &&
      other.point == point &&
      other.time == time &&
      other.battery == battery;

  @override
  int get hashCode => Object.hash(userId, point, time, battery);
}
