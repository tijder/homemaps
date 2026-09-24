import 'package:flutter/foundation.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Het Dawarich-account waarmee is ingelogd. De API-sleutel staat niet in de
/// gewone opslag, zie `dawarichGeheimProvider`.
@immutable
class DawarichAccount {
  const DawarichAccount({
    required this.server,
    required this.email,
    this.userId,
    this.familie = true,
    this.toonFamilie = false,
  });

  /// Zonder `/` aan het eind, bijvoorbeeld `https://dawarich.example`.
  final String server;
  final String email;

  /// Null na inloggen met een geplakte sleutel: `/users/me` geeft hem niet.
  final int? userId;

  /// Kan dit account familie gebruiken (`features.family`)? Op Dawarich Cloud
  /// alleen met het Family-abonnement.
  final bool familie;

  /// Familieleden op de kaart tonen.
  final bool toonFamilie;

  DawarichAccount kopie({bool? familie, bool? toonFamilie}) => DawarichAccount(
    server: server,
    email: email,
    userId: userId,
    familie: familie ?? this.familie,
    toonFamilie: toonFamilie ?? this.toonFamilie,
  );

  Map<String, Object?> naarMap() => {
    'server': server,
    'email': email,
    'userId': userId,
    'familie': familie,
    'toonFamilie': toonFamilie,
  };

  static DawarichAccount? vanMap(Object? ruw) {
    if (ruw is! Map) return null;
    final server = ruw['server'];
    if (server is! String || server.isEmpty) return null;
    return DawarichAccount(
      server: server,
      email: ruw['email'] as String? ?? '',
      userId: (ruw['userId'] as num?)?.toInt(),
      familie: ruw['familie'] != false,
      toonFamilie: ruw['toonFamilie'] == true,
    );
  }
}

/// Hoe lang je je locatie met de familie deelt; de waarden zijn die van
/// Dawarich.
enum DeelDuur {
  uur1('1h'),
  uur6('6h'),
  uur12('12h'),
  uur24('24h'),
  altijd('permanent');

  const DeelDuur(this.waarde);

  final String waarde;

  static DeelDuur? van(Object? waarde) =>
      values.where((d) => d.waarde == waarde).firstOrNull;
}

/// Jouw plek in de familie, uit `/api/v1/families/mine`.
@immutable
class FamilieStatus {
  const FamilieStatus({
    required this.naam,
    required this.delenAan,
    this.duur,
    this.verlooptOm,
    this.leden = const [],
  });

  final String naam;
  final bool delenAan;

  /// Null als Dawarich een eigen aantal uren gaf.
  final DeelDuur? duur;

  /// Null bij "altijd".
  final DateTime? verlooptOm;

  /// De e-mailadressen van de anderen in de familie.
  final List<String> leden;

  factory FamilieStatus.vanJson(Map<String, dynamic> json) {
    final delen = (json['me'] as Map?)?['sharing'] as Map? ?? const {};
    final mijnId = (json['me'] as Map?)?['user_id'];
    return FamilieStatus(
      naam: (json['family'] as Map?)?['name'] as String? ?? '',
      delenAan: delen['enabled'] == true,
      duur: DeelDuur.van(delen['duration']),
      verlooptOm: DateTime.tryParse('${delen['expires_at']}')?.toLocal(),
      leden: [
        for (final lid in (json['members'] as List? ?? const []))
          if (lid is Map && lid['user_id'] != mijnId) '${lid['email']}',
      ],
    );
  }
}

/// De laatste plek van een familielid dat zijn locatie deelt.
@immutable
class FamilieLocatie {
  const FamilieLocatie({
    required this.userId,
    required this.email,
    required this.initiaal,
    required this.punt,
    required this.tijd,
    this.batterij,
  });

  final int userId;
  final String email;
  final String initiaal;
  final LatLng punt;
  final DateTime tijd;

  /// Procent, als Dawarich het weet.
  final int? batterij;

  /// Eén regel uit `/api/v1/families/locations`; null als er iets ontbreekt.
  static FamilieLocatie? vanJson(Map<String, dynamic> json) {
    final id = json['user_id'], lat = json['latitude'], lon = json['longitude'];
    if (id is! num) return null;
    final breedte = lat is num ? lat.toDouble() : double.tryParse('$lat');
    final lengte = lon is num ? lon.toDouble() : double.tryParse('$lon');
    if (breedte == null || lengte == null) return null;
    final ts = json['timestamp'];
    final tijd = ts is num
        ? DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000)
        : DateTime.tryParse('$ts')?.toLocal() ?? DateTime.now();
    final email = json['email'] as String? ?? '';
    final initiaal = json['email_initial'] as String? ?? '';
    return FamilieLocatie(
      userId: id.toInt(),
      email: email,
      initiaal:
          (initiaal.isNotEmpty
                  ? initiaal
                  : email.isNotEmpty
                  ? email.substring(0, 1)
                  : '?')
              .toUpperCase(),
      punt: LatLng(breedte, lengte),
      tijd: tijd,
      batterij: (json['battery'] as num?)?.round(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FamilieLocatie &&
      other.userId == userId &&
      other.punt == punt &&
      other.tijd == tijd &&
      other.batterij == batterij;

  @override
  int get hashCode => Object.hash(userId, punt, tijd, batterij);
}
