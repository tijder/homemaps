import 'package:flutter/foundation.dart';

/// De velden die elk sjabloon verstuurt, onder zijn eigen naam: breedte,
/// lengte, nauwkeurigheid (m), hoogte (m), snelheid (m/s), tijd (Unix-seconden)
/// en koers (graden).
const basisVelden = ['lat', 'lon', 'acc', 'alt', 'vel', 'tst', 'bear'];

enum DeelMethode { post, get }

enum DeelInlog { geen, basic, bearer }

/// De servers waar Colota mee praat, met dezelfde veldnamen en vaste velden
/// (zie Colota's `API_TEMPLATES`), zodat een server die Colota slikt ook dit
/// slikt.
enum DeelSjabloon {
  dawarich(
    naam: 'Dawarich',
    voorbeeldUrl:
        'https://dawarich.example/api/v1/owntracks/points?api_key=SLEUTEL',
    velden: {'bear': 'cog'},
    extra: {'_type': 'location'},
  ),
  geopulse(
    naam: 'GeoPulse',
    voorbeeldUrl: 'https://geopulse.example/api/colota',
  ),
  overland(
    naam: 'Overland',
    voorbeeldUrl: 'https://overland.example/',
    extra: {'device_id': 'homemaps'},
    batch: true,
  ),
  owntracks(
    naam: 'OwnTracks',
    voorbeeldUrl: 'https://owntracks.example/pub',
    velden: {'bear': 'cog'},
    extra: {'_type': 'location', 'tid': 'HM'},
  ),
  phonetrack(
    naam: 'PhoneTrack',
    voorbeeldUrl: 'https://nextcloud.example/apps/phonetrack/log/owntracks/SESSIE/APPARAAT',
    velden: {'vel': 'speed', 'tst': 'timestamp', 'bear': 'bearing'},
    extra: {'useragent': 'HomeMaps'},
  ),
  reitti(
    naam: 'Reitti',
    voorbeeldUrl: 'https://reitti.example/api/location',
    extra: {'_type': 'location'},
  ),
  traccar(
    naam: 'Traccar',
    voorbeeldUrl: 'http://192.168.1.10:5055',
    velden: {
      'acc': 'accuracy',
      'alt': 'altitude',
      'vel': 'speed',
      'tst': 'timestamp',
      'bear': 'bearing',
    },
    extra: {'id': 'homemaps'},
    methode: DeelMethode.get,
  ),
  aangepast(naam: null, voorbeeldUrl: 'https://server.example/locatie');

  const DeelSjabloon({
    required this.naam,
    required this.voorbeeldUrl,
    this.velden = const {},
    this.extra = const {},
    this.methode = DeelMethode.post,
    this.batch = false,
  });

  /// De naam van de server; null bij [aangepast] (die heeft een vertaling).
  final String? naam;
  final String voorbeeldUrl;

  /// Afwijkende veldnamen; wat er niet in staat heet zoals in [basisVelden].
  final Map<String, String> velden;

  /// Velden die er altijd bij gaan, zoals OwnTracks' `_type`.
  final Map<String, String> extra;
  final DeelMethode methode;

  /// Overland: alle punten in één verzoek, als GeoJSON.
  final bool batch;

  /// Bij Traccar (OsmAnd-GET of JSON-POST) en een eigen server valt er te
  /// kiezen.
  bool get methodeKiesbaar => this == traccar || this == aangepast;
}

/// Hoe de positie tijdens het navigeren gedeeld wordt. Het wachtwoord of de
/// token ([geheim]) staat niet in de gewone opslag, zie `GeheimOpslag`.
@immutable
class DeelInstellingen {
  DeelInstellingen({
    this.aan = false,
    this.sjabloon = DeelSjabloon.owntracks,
    this.url = '',
    DeelMethode? methode,
    this.veldnamen = const {},
    Map<String, String>? extraVelden,
    this.inlog = DeelInlog.geen,
    this.gebruiker = '',
    this.geheim = '',
    this.interval = 10,
    this.minAfstand = 20,
  }) : methode = methode ?? sjabloon.methode,
       extraVelden = extraVelden ?? sjabloon.extra;

  final bool aan;
  final DeelSjabloon sjabloon;
  final String url;
  final DeelMethode methode;

  /// Alleen bij [DeelSjabloon.aangepast]: eigen namen voor [basisVelden].
  final Map<String, String> veldnamen;

  /// Vaste velden die meegaan; bij het kiezen van een sjabloon diens [extra].
  final Map<String, String> extraVelden;
  final DeelInlog inlog;
  final String gebruiker;

  /// Het wachtwoord (Basic) of de token (Bearer).
  final String geheim;

  /// Een nieuw punt na zoveel seconden, of na [minAfstand] meter.
  final int interval;
  final int minAfstand;

  /// Kan er iets verstuurd worden?
  bool get compleet {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme.startsWith('http') && uri.host.isNotEmpty;
  }

  /// De naam waaronder elk basisveld verstuurd wordt.
  Map<String, String> get effectieveVelden => {
    for (final veld in basisVelden)
      veld: sjabloon == DeelSjabloon.aangepast
          ? (veldnamen[veld]?.trim().isNotEmpty ?? false)
                ? veldnamen[veld]!.trim()
                : veld
          : sjabloon.velden[veld] ?? veld,
  };

  /// Een ander sjabloon: met diens methode en vaste velden.
  DeelInstellingen metSjabloon(DeelSjabloon nieuw) =>
      kopie(sjabloon: nieuw, methode: nieuw.methode, extraVelden: nieuw.extra);

  DeelInstellingen kopie({
    bool? aan,
    DeelSjabloon? sjabloon,
    String? url,
    DeelMethode? methode,
    Map<String, String>? veldnamen,
    Map<String, String>? extraVelden,
    DeelInlog? inlog,
    String? gebruiker,
    String? geheim,
    int? interval,
    int? minAfstand,
  }) => DeelInstellingen(
    aan: aan ?? this.aan,
    sjabloon: sjabloon ?? this.sjabloon,
    url: url ?? this.url,
    methode: methode ?? this.methode,
    veldnamen: veldnamen ?? this.veldnamen,
    extraVelden: extraVelden ?? this.extraVelden,
    inlog: inlog ?? this.inlog,
    gebruiker: gebruiker ?? this.gebruiker,
    geheim: geheim ?? this.geheim,
    interval: interval ?? this.interval,
    minAfstand: minAfstand ?? this.minAfstand,
  );

  /// Voor de opslag, zonder [geheim].
  Map<String, Object> naarMap() => {
    'aan': aan,
    'sjabloon': sjabloon.name,
    'url': url,
    'methode': methode.name,
    'veldnamen': veldnamen,
    'extraVelden': extraVelden,
    'inlog': inlog.name,
    'gebruiker': gebruiker,
    'interval': interval,
    'minAfstand': minAfstand,
  };

  static DeelInstellingen vanMap(Object? ruw) {
    if (ruw is! Map) return DeelInstellingen();
    T uit<T extends Enum>(List<T> waarden, Object? naam, T anders) =>
        waarden.firstWhere((w) => w.name == naam, orElse: () => anders);
    Map<String, String>? tekstMap(Object? m) =>
        m is Map ? {for (final e in m.entries) '${e.key}': '${e.value}'} : null;
    final sjabloon = uit(
      DeelSjabloon.values,
      ruw['sjabloon'],
      DeelSjabloon.owntracks,
    );
    return DeelInstellingen(
      aan: ruw['aan'] == true,
      sjabloon: sjabloon,
      url: ruw['url'] as String? ?? '',
      methode: uit(DeelMethode.values, ruw['methode'], sjabloon.methode),
      veldnamen: tekstMap(ruw['veldnamen']) ?? const {},
      extraVelden: tekstMap(ruw['extraVelden']) ?? sjabloon.extra,
      inlog: uit(DeelInlog.values, ruw['inlog'], DeelInlog.geen),
      gebruiker: ruw['gebruiker'] as String? ?? '',
      interval: (ruw['interval'] as num?)?.toInt() ?? 10,
      minAfstand: (ruw['minAfstand'] as num?)?.toInt() ?? 20,
    );
  }
}

/// Eén gedeelde positie; zo staat hij ook in de wachtrij.
@immutable
class DeelPunt {
  const DeelPunt({
    required this.lat,
    required this.lon,
    required this.tst,
    this.acc,
    this.alt,
    this.vel,
    this.bear,
  });

  final double lat;
  final double lon;

  /// Unix-tijd in seconden.
  final int tst;
  final double? acc;
  final double? alt;

  /// m/s.
  final double? vel;
  final double? bear;

  Map<String, Object> naarMap() => {
    'lat': lat,
    'lon': lon,
    'tst': tst,
    'acc': ?acc,
    'alt': ?alt,
    'vel': ?vel,
    'bear': ?bear,
  };

  static DeelPunt vanMap(Map<dynamic, dynamic> m) => DeelPunt(
    lat: (m['lat'] as num).toDouble(),
    lon: (m['lon'] as num).toDouble(),
    tst: (m['tst'] as num).toInt(),
    acc: (m['acc'] as num?)?.toDouble(),
    alt: (m['alt'] as num?)?.toDouble(),
    vel: (m['vel'] as num?)?.toDouble(),
    bear: (m['bear'] as num?)?.toDouble(),
  );
}
