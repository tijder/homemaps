import 'package:flutter/foundation.dart';

/// The fields every template sends, under its own name: latitude, longitude,
/// accuracy (m), altitude (m), speed (m/s), time (Unix seconds) and bearing
/// (degrees).
const baseFields = ['lat', 'lon', 'acc', 'alt', 'vel', 'tst', 'bear'];

enum ShareMethod { post, get }

enum ShareAuth { none, basic, bearer }

/// The servers Colota talks to, with the same field names and fixed fields
/// (see Colota's `API_TEMPLATES`), so a server that accepts Colota accepts
/// this too.
enum ShareTemplate {
  /// Unlike Colota not via OwnTracks but via `/api/v1/points`: that also keeps
  /// the heading and the mode of transport, and takes 100 points at a time.
  /// The format is Overland's.
  dawarich(
    label: 'Dawarich',
    exampleUrl: 'https://dawarich.example/api/v1/points?api_key=KEY',
    extra: {'device_id': 'homemaps'},
    batch: true,
  ),
  geopulse(
    label: 'GeoPulse',
    exampleUrl: 'https://geopulse.example/api/colota',
  ),
  overland(
    label: 'Overland',
    exampleUrl: 'https://overland.example/',
    extra: {'device_id': 'homemaps'},
    batch: true,
  ),
  owntracks(
    label: 'OwnTracks',
    exampleUrl: 'https://owntracks.example/pub',
    fields: {'bear': 'cog'},
    extra: {'_type': 'location', 'tid': 'HM'},
  ),
  phonetrack(
    label: 'PhoneTrack',
    exampleUrl: 'https://nextcloud.example/apps/phonetrack/log/owntracks/SESSION/DEVICE',
    fields: {'vel': 'speed', 'tst': 'timestamp', 'bear': 'bearing'},
    extra: {'useragent': 'HomeMaps'},
  ),
  reitti(
    label: 'Reitti',
    exampleUrl: 'https://reitti.example/api/location',
    extra: {'_type': 'location'},
  ),
  traccar(
    label: 'Traccar',
    exampleUrl: 'http://192.168.1.10:5055',
    fields: {
      'acc': 'accuracy',
      'alt': 'altitude',
      'vel': 'speed',
      'tst': 'timestamp',
      'bear': 'bearing',
    },
    extra: {'id': 'homemaps'},
    method: ShareMethod.get,
  ),
  custom(label: null, exampleUrl: 'https://server.example/location');

  const ShareTemplate({
    required this.label,
    required this.exampleUrl,
    this.fields = const {},
    this.extra = const {},
    this.method = ShareMethod.post,
    this.batch = false,
  });

  /// The server's name; null for [custom] (that one has a translation).
  final String? label;
  final String exampleUrl;

  /// Differing field names; anything not in here is named as in [baseFields].
  final Map<String, String> fields;

  /// Fields that are always sent, like OwnTracks' `_type`.
  final Map<String, String> extra;
  final ShareMethod method;

  /// Overland: all points in one request, as GeoJSON.
  final bool batch;

  /// For Traccar (OsmAnd GET or JSON POST) and a custom server there's a
  /// choice.
  bool get methodChoosable => this == traccar || this == custom;
}

/// How the position is shared while navigating. The password or token
/// ([secret]) isn't in regular storage, see `SecretStore`.
@immutable
class ShareSettings {
  ShareSettings({
    this.enabled = false,
    this.template = ShareTemplate.owntracks,
    this.url = '',
    ShareMethod? method,
    this.fieldNames = const {},
    Map<String, String>? extraFields,
    this.auth = ShareAuth.none,
    this.username = '',
    this.secret = '',
    this.interval = 10,
    this.minDistance = 20,
  }) : method = method ?? template.method,
       extraFields = extraFields ?? template.extra;

  final bool enabled;
  final ShareTemplate template;
  final String url;
  final ShareMethod method;

  /// Only for [ShareTemplate.custom]: custom names for [baseFields].
  final Map<String, String> fieldNames;

  /// Fixed fields that are sent along; when picking a template, its [extra].
  final Map<String, String> extraFields;
  final ShareAuth auth;
  final String username;

  /// The password (Basic) or the token (Bearer).
  final String secret;

  /// A new point after this many seconds, or after [minDistance] meters.
  final int interval;
  final int minDistance;

  /// Can anything be sent?
  bool get complete {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme.startsWith('http') && uri.host.isNotEmpty;
  }

  /// The name each base field is sent under.
  Map<String, String> get effectiveFields => {
    for (final field in baseFields)
      field: template == ShareTemplate.custom
          ? (fieldNames[field]?.trim().isNotEmpty ?? false)
                ? fieldNames[field]!.trim()
                : field
          : template.fields[field] ?? field,
  };

  /// A different template: with its method and fixed fields.
  ShareSettings withTemplate(ShareTemplate newValue) => copyWith(
    template: newValue,
    method: newValue.method,
    extraFields: newValue.extra,
  );

  ShareSettings copyWith({
    bool? enabled,
    ShareTemplate? template,
    String? url,
    ShareMethod? method,
    Map<String, String>? fieldNames,
    Map<String, String>? extraFields,
    ShareAuth? auth,
    String? username,
    String? secret,
    int? interval,
    int? minDistance,
  }) => ShareSettings(
    enabled: enabled ?? this.enabled,
    template: template ?? this.template,
    url: url ?? this.url,
    method: method ?? this.method,
    fieldNames: fieldNames ?? this.fieldNames,
    extraFields: extraFields ?? this.extraFields,
    auth: auth ?? this.auth,
    username: username ?? this.username,
    secret: secret ?? this.secret,
    interval: interval ?? this.interval,
    minDistance: minDistance ?? this.minDistance,
  );

  /// For storage, without [secret].
  Map<String, Object> toMap() => {
    'enabled': enabled,
    'template': template.name,
    'url': url,
    'method': method.name,
    'fieldNames': fieldNames,
    'extraFields': extraFields,
    'auth': auth.name,
    'username': username,
    'interval': interval,
    'minDistance': minDistance,
  };

  static ShareSettings fromMap(Object? raw) {
    if (raw is! Map) return ShareSettings();
    T pick<T extends Enum>(List<T> values, Object? label, T fallback) =>
        values.firstWhere((w) => w.name == label, orElse: () => fallback);
    Map<String, String>? stringMap(Object? m) =>
        m is Map ? {for (final e in m.entries) '${e.key}': '${e.value}'} : null;
    final template = pick(
      ShareTemplate.values,
      raw['template'],
      ShareTemplate.owntracks,
    );
    var url = raw['url'] as String? ?? '';
    var extra = stringMap(raw['extraFields']);
    // Dawarich used to go via OwnTracks; see ShareTemplate.dawarich. Both
    // endpoints take the same api_key.
    if (template == ShareTemplate.dawarich &&
        url.contains('/api/v1/owntracks/points')) {
      url = url.replaceFirst('/api/v1/owntracks/points', '/api/v1/points');
      if (mapEquals(extra, const {'_type': 'location'})) extra = null;
    }
    return ShareSettings(
      enabled: raw['enabled'] == true,
      template: template,
      url: url,
      method: pick(ShareMethod.values, raw['method'], template.method),
      fieldNames: stringMap(raw['fieldNames']) ?? const {},
      extraFields: extra ?? template.extra,
      auth: pick(ShareAuth.values, raw['auth'], ShareAuth.none),
      username: raw['username'] as String? ?? '',
      interval: (raw['interval'] as num?)?.toInt() ?? 10,
      minDistance: (raw['minDistance'] as num?)?.toInt() ?? 20,
    );
  }
}

/// One shared position; this is also how it's stored in the queue.
@immutable
class SharedPoint {
  const SharedPoint({
    required this.lat,
    required this.lon,
    required this.tst,
    this.acc,
    this.alt,
    this.vel,
    this.bear,
    this.vac,
    this.bearAcc,
    this.batt,
    this.bs,
    this.transport,
  });

  final double lat;
  final double lon;

  /// Unix time in seconds.
  final int tst;
  final double? acc;
  final double? alt;

  /// m/s.
  final double? vel;
  final double? bear;

  /// Accuracy of the altitude (m) and of the bearing (degrees).
  final double? vac;
  final double? bearAcc;

  /// Battery in percent, and `unplugged`, `charging` or `full`.
  final int? batt;
  final String? bs;

  /// How you're travelling, as Overland calls it: `driving`, `cycling` or
  /// `walking`.
  final String? transport;

  Map<String, Object> toMap() => {
    'lat': lat,
    'lon': lon,
    'tst': tst,
    'acc': ?acc,
    'alt': ?alt,
    'vel': ?vel,
    'bear': ?bear,
    'vac': ?vac,
    'bearAcc': ?bearAcc,
    'batt': ?batt,
    'bs': ?bs,
    'transport': ?transport,
  };

  static SharedPoint fromMap(Map<dynamic, dynamic> m) => SharedPoint(
    lat: (m['lat'] as num).toDouble(),
    lon: (m['lon'] as num).toDouble(),
    tst: (m['tst'] as num).toInt(),
    acc: (m['acc'] as num?)?.toDouble(),
    alt: (m['alt'] as num?)?.toDouble(),
    vel: (m['vel'] as num?)?.toDouble(),
    bear: (m['bear'] as num?)?.toDouble(),
    vac: (m['vac'] as num?)?.toDouble(),
    bearAcc: (m['bearAcc'] as num?)?.toDouble(),
    batt: (m['batt'] as num?)?.toInt(),
    bs: m['bs'] as String?,
    transport: m['transport'] as String?,
  );
}
