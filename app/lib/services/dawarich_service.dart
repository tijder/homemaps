import 'package:dio/dio.dart';

import '../models/dawarich.dart';

/// Wat er mis kan gaan; de schermen maken er een vertaalde tekst van.
enum DawarichFoutSoort {
  /// Verkeerd e-mailadres, wachtwoord, code of sleutel.
  inlog,

  /// Inloggen met een wachtwoord staat uit op deze server (alleen OIDC).
  wachtwoordUit,

  /// Te vaak een verkeerde code: even geblokkeerd.
  geblokkeerd,

  /// Je zit (nog) niet in een familie.
  geenFamilie,

  /// Familie zit niet in dit abonnement (Dawarich Cloud).
  geenAbonnement,

  /// Geen Dawarich, of niet te bereiken (op het web ook: geen CORS).
  verbinding,

  /// Een ander antwoord dan verwacht.
  onbekend,
}

class DawarichFout implements Exception {
  const DawarichFout(this.soort, [this.detail]);

  final DawarichFoutSoort soort;

  /// De status of de tekst van de server, voor bij de melding.
  final String? detail;

  @override
  String toString() => 'DawarichFout(${soort.name}, $detail)';
}

/// Het antwoord op inloggen met e-mail en wachtwoord.
sealed class DawarichLogin {
  const DawarichLogin();
}

class DawarichIngelogd extends DawarichLogin {
  const DawarichIngelogd(this.sleutel, this.account);

  final String sleutel;
  final DawarichAccount account;
}

/// Het account heeft tweestapsverificatie: eerst nog de code, met deze token.
class DawarichTweeStap extends DawarichLogin {
  const DawarichTweeStap(this.token);

  final String token;
}

/// Praat met de API van Dawarich (`/api/v1`), met de API-sleutel als Bearer.
class DawarichService {
  DawarichService(this._dio);

  final Dio _dio;

  /// Een ingevuld adres als basis: met `https://` als het schema ontbreekt,
  /// zonder `/` aan het eind. Null als het geen adres is.
  static String? normaliseer(String tekst) {
    var s = tekst.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'https://$s';
    final uri = Uri.tryParse(s);
    if (uri == null || !uri.scheme.startsWith('http') || uri.host.isEmpty) {
      return null;
    }
    return s.replaceFirst(RegExp(r'/+$'), '');
  }

  Future<Response<dynamic>> _vraag(
    String methode,
    String server,
    String pad, {
    String? sleutel,
    Object? data,
  }) async {
    try {
      return await _dio.request<dynamic>(
        '$server/api/v1/$pad',
        data: data,
        options: Options(
          method: methode,
          headers: {
            'Authorization': ?(sleutel == null ? null : 'Bearer $sleutel'),
          },
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      throw DawarichFout(
        DawarichFoutSoort.verbinding,
        e.message ?? e.type.name,
      );
    }
  }

  static Map<String, dynamic> _json(Response<dynamic> antwoord) {
    final data = antwoord.data;
    if (data is Map) return data.cast<String, dynamic>();
    // Geen JSON: waarschijnlijk geen Dawarich op dit adres.
    throw DawarichFout(
      DawarichFoutSoort.verbinding,
      'HTTP ${antwoord.statusCode}',
    );
  }

  static Never _fout(Response<dynamic> antwoord) {
    final status = antwoord.statusCode ?? 0;
    final data = antwoord.data;
    final tekst = data is Map
        ? '${data['message'] ?? data['error'] ?? ''}'
        : '';
    throw DawarichFout(switch (status) {
      401 => DawarichFoutSoort.inlog,
      423 => DawarichFoutSoort.geblokkeerd,
      404 => DawarichFoutSoort.geenFamilie,
      403 when data is Map && data['error'] == 'family_plan_required' =>
        DawarichFoutSoort.geenAbonnement,
      403 => DawarichFoutSoort.wachtwoordUit,
      _ => DawarichFoutSoort.onbekend,
    }, tekst.isEmpty ? 'HTTP $status' : tekst);
  }

  DawarichIngelogd _ingelogd(String server, Map<String, dynamic> json) {
    final sleutel = json['api_key'];
    if (sleutel is! String || sleutel.isEmpty) {
      throw const DawarichFout(DawarichFoutSoort.onbekend, 'geen api_key');
    }
    return DawarichIngelogd(
      sleutel,
      DawarichAccount(
        server: server,
        email: json['email'] as String? ?? '',
        userId: (json['user_id'] as num?)?.toInt(),
      ),
    );
  }

  /// `POST /auth/login`. Heeft het account tweestapsverificatie, dan volgt
  /// [otp] met de token uit [DawarichTweeStap].
  Future<DawarichLogin> login(
    String server,
    String email,
    String wachtwoord,
  ) async {
    final antwoord = await _vraag(
      'POST',
      server,
      'auth/login',
      data: {'email': email, 'password': wachtwoord},
    );
    final status = antwoord.statusCode ?? 0;
    if (status == 202) {
      final token = _json(antwoord)['challenge_token'];
      if (token is String) return DawarichTweeStap(token);
    }
    if (status != 200) _fout(antwoord);
    return _ingelogd(server, _json(antwoord));
  }

  /// `POST /auth/otp_challenge`: de code uit de authenticator-app (of een
  /// back-upcode).
  Future<DawarichIngelogd> otp(String server, String token, String code) async {
    final antwoord = await _vraag(
      'POST',
      server,
      'auth/otp_challenge',
      data: {'challenge_token': token, 'otp_code': code.trim()},
    );
    if (antwoord.statusCode != 200) _fout(antwoord);
    return _ingelogd(server, _json(antwoord));
  }

  /// Een geplakte sleutel controleren met `GET /users/me`.
  Future<DawarichAccount> controleerSleutel(
    String server,
    String sleutel,
  ) async {
    final antwoord = await _vraag('GET', server, 'users/me', sleutel: sleutel);
    if (antwoord.statusCode != 200) _fout(antwoord);
    final json = _json(antwoord);
    final gebruiker = (json['user'] as Map?) ?? const {};
    return DawarichAccount(
      server: server,
      email: gebruiker['email'] as String? ?? '',
      familie: (json['features'] as Map?)?['family'] != false,
    );
  }

  /// `GET /families/mine`.
  Future<FamilieStatus> familie(String server, String sleutel) async {
    final antwoord = await _vraag(
      'GET',
      server,
      'families/mine',
      sleutel: sleutel,
    );
    if (antwoord.statusCode != 200) _fout(antwoord);
    return FamilieStatus.vanJson(_json(antwoord));
  }

  /// `PATCH /families/sharing`: je eigen locatie met de familie delen, of
  /// niet meer.
  Future<void> zetDelen(
    String server,
    String sleutel, {
    required bool aan,
    DeelDuur? duur,
  }) async {
    final antwoord = await _vraag(
      'PATCH',
      server,
      'families/sharing',
      sleutel: sleutel,
      data: {'enabled': aan, 'duration': ?duur?.waarde},
    );
    if (antwoord.statusCode != 200) _fout(antwoord);
  }

  /// `GET /families/locations`: de laatste plek van iedereen die deelt,
  /// jijzelf ook.
  Future<List<FamilieLocatie>> locaties(String server, String sleutel) async {
    final antwoord = await _vraag(
      'GET',
      server,
      'families/locations',
      sleutel: sleutel,
    );
    if (antwoord.statusCode != 200) _fout(antwoord);
    return [
      for (final regel in (_json(antwoord)['locations'] as List? ?? const []))
        if (regel is Map)
          ?FamilieLocatie.vanJson(regel.cast<String, dynamic>()),
    ];
  }
}
