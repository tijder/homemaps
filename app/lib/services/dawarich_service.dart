import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/dawarich.dart';

/// What can go wrong; the screens turn it into a translated text.
enum DawarichErrorKind {
  /// Wrong email address, password, code or key.
  auth,

  /// Password login is disabled on this server (OIDC only).
  passwordDisabled,

  /// Wrong code too often: temporarily blocked.
  blocked,

  /// You're not in a family (yet).
  noFamily,

  /// Family isn't part of this plan (Dawarich Cloud).
  noSubscription,

  /// Unreachable (on the web also: no CORS).
  connection,

  /// Something answers, but not Dawarich's API: a different address, or a
  /// login proxy (like Authelia) that doesn't let `/api/v1` through.
  notDawarich,

  /// A different response than expected.
  unknown,
}

class DawarichError implements Exception {
  const DawarichError(this.kind, [this.detail]);

  final DawarichErrorKind kind;

  /// The server's status or text, to show with the message.
  final String? detail;

  @override
  String toString() => 'DawarichError(${kind.name}, $detail)';
}

/// The response to logging in with email and password.
sealed class DawarichLogin {
  const DawarichLogin();
}

class DawarichSignedIn extends DawarichLogin {
  const DawarichSignedIn(this.key, this.account);

  final String key;
  final DawarichAccount account;
}

/// The account has two-factor authentication: the code first, with this token.
class DawarichTwoFactor extends DawarichLogin {
  const DawarichTwoFactor(this.token);

  final String token;
}

/// Talks to Dawarich's API (`/api/v1`), with the API key as Bearer.
class DawarichService {
  DawarichService(this._dio);

  final Dio _dio;

  /// An entered address as base: with `https://` if the scheme is missing,
  /// without a trailing `/`. Null if it isn't an address.
  static String? normalize(String text) {
    var s = text.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'https://$s';
    final uri = Uri.tryParse(s);
    if (uri == null || !uri.scheme.startsWith('http') || uri.host.isEmpty) {
      return null;
    }
    return s.replaceFirst(RegExp(r'/+$'), '');
  }

  /// Where Dawarich redirects after logging in on the website when the client
  /// is `android` or `ios`: `/auth/ios/success?token=<JWT>`.
  static bool isHandoff(Uri uri) =>
      uri.path.endsWith('/auth/ios/success') &&
      (uri.queryParameters['token']?.isNotEmpty ?? false);

  /// The API key from that address. The JWT's payload is `{api_key, exp}`;
  /// Dawarich doesn't verify the signature itself either, just like its own
  /// apps. Null if there's no key in it.
  static String? keyFromHandoff(Uri uri) {
    if (!isHandoff(uri)) return null;
    final parts = uri.queryParameters['token']!.split('.');
    if (parts.length != 3) return null;
    try {
      final content = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final key = content is Map ? content['api_key'] : null;
      return key is String && key.isNotEmpty ? key : null;
    } on FormatException {
      return null;
    }
  }

  Future<Response<dynamic>> _request(
    String method,
    String server,
    String path, {
    String? key,
    Object? data,
  }) async {
    try {
      return await _dio.request<dynamic>(
        '$server/api/v1/$path',
        data: data,
        options: Options(
          method: method,
          headers: {'Authorization': ?(key == null ? null : 'Bearer $key')},
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw DawarichError(
        DawarichErrorKind.connection,
        e.message ?? e.type.name,
      );
    }
  }

  static Map<String, dynamic> _json(Response<dynamic> response) {
    final data = response.data;
    if (data is Map) return data.cast<String, dynamic>();
    // No JSON: probably no Dawarich at this address.
    throw DawarichError(
      DawarichErrorKind.notDawarich,
      'HTTP ${response.statusCode}',
    );
  }

  /// The version from the response; in the browser only if the server exposes
  /// the header (CORS).
  static String? _version(Response<dynamic> response) =>
      response.headers.value('x-dawarich-version');

  /// Is there a Dawarich here? `GET /health` works without logging in. Returns
  /// the version, if readable.
  Future<({String? version})> connect(String server) async {
    final response = await _request('GET', server, 'health');
    if (response.statusCode != 200 || _json(response)['status'] != 'ok') {
      throw DawarichError(
        DawarichErrorKind.notDawarich,
        'HTTP ${response.statusCode}',
      );
    }
    return (version: _version(response));
  }

  /// Does the key still work? Returns the version; [DawarichErrorKind.auth] if
  /// the key isn't valid (anymore).
  Future<({String? version})> check(String server, String key) async {
    final response = await _request('GET', server, 'users/me', key: key);
    if (response.statusCode != 200) _error(response);
    _json(response);
    return (version: _version(response));
  }

  static Never _error(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    final data = response.data;
    final text = data is Map ? '${data['message'] ?? data['error'] ?? ''}' : '';
    throw DawarichError(switch (status) {
      401 => DawarichErrorKind.auth,
      423 => DawarichErrorKind.blocked,
      404 => DawarichErrorKind.noFamily,
      403 when data is Map && data['error'] == 'family_plan_required' =>
        DawarichErrorKind.noSubscription,
      403 => DawarichErrorKind.passwordDisabled,
      _ => DawarichErrorKind.unknown,
    }, text.isEmpty ? 'HTTP $status' : text);
  }

  DawarichSignedIn _signedIn(String server, Map<String, dynamic> json) {
    final key = json['api_key'];
    if (key is! String || key.isEmpty) {
      throw const DawarichError(DawarichErrorKind.unknown, 'no api_key');
    }
    return DawarichSignedIn(
      key,
      DawarichAccount(
        server: server,
        email: json['email'] as String? ?? '',
        userId: (json['user_id'] as num?)?.toInt(),
      ),
    );
  }

  /// `POST /auth/login`. If the account has two-factor authentication, [otp]
  /// follows with the token from [DawarichTwoFactor].
  Future<DawarichLogin> login(
    String server,
    String email,
    String password,
  ) async {
    final response = await _request(
      'POST',
      server,
      'auth/login',
      data: {'email': email, 'password': password},
    );
    final status = response.statusCode ?? 0;
    if (status == 202) {
      final token = _json(response)['challenge_token'];
      if (token is String) return DawarichTwoFactor(token);
    }
    if (status != 200) _error(response);
    return _signedIn(server, _json(response));
  }

  /// `POST /auth/otp_challenge`: the code from the authenticator app (or a
  /// backup code).
  Future<DawarichSignedIn> otp(String server, String token, String code) async {
    final response = await _request(
      'POST',
      server,
      'auth/otp_challenge',
      data: {'challenge_token': token, 'otp_code': code.trim()},
    );
    if (response.statusCode != 200) _error(response);
    return _signedIn(server, _json(response));
  }

  /// Check a pasted key with `GET /users/me`.
  Future<DawarichAccount> checkKey(String server, String key) async {
    final response = await _request('GET', server, 'users/me', key: key);
    if (response.statusCode != 200) _error(response);
    final json = _json(response);
    final user = (json['user'] as Map?) ?? const {};
    return DawarichAccount(
      server: server,
      email: user['email'] as String? ?? '',
      family: (json['features'] as Map?)?['family'] != false,
    );
  }

  /// `GET /families/mine`.
  Future<FamilyStatus> family(String server, String key) async {
    final response = await _request('GET', server, 'families/mine', key: key);
    if (response.statusCode != 200) _error(response);
    return FamilyStatus.fromJson(_json(response));
  }

  /// `PATCH /families/sharing`: share your own location with the family, or
  /// stop sharing.
  Future<void> setSharing(
    String server,
    String key, {
    required bool enabled,
    ShareDuration? duration,
  }) async {
    final response = await _request(
      'PATCH',
      server,
      'families/sharing',
      key: key,
      data: {'enabled': enabled, 'duration': ?duration?.value},
    );
    if (response.statusCode != 200) _error(response);
  }

  /// `GET /families/locations`: the last position of everyone who shares,
  /// including yourself.
  Future<List<FamilyLocation>> locations(String server, String key) async {
    final response = await _request(
      'GET',
      server,
      'families/locations',
      key: key,
    );
    if (response.statusCode != 200) _error(response);
    return [
      for (final row in (_json(response)['locations'] as List? ?? const []))
        if (row is Map) ?FamilyLocation.fromJson(row.cast<String, dynamic>()),
    ];
  }
}
