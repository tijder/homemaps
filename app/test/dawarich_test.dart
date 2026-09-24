import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/models/dawarich.dart';
import 'package:homemaps/models/locatie_delen.dart';
import 'package:homemaps/providers/dawarich.dart';
import 'package:homemaps/providers/diensten.dart';
import 'package:homemaps/providers/locatie_delen.dart';
import 'package:homemaps/screens/instellingen/instellingen_screen.dart';
import 'package:homemaps/services/dawarich_service.dart';
import 'package:homemaps/utils/opmaak.dart';

const server = 'https://dawarich.test';

/// Speelt Dawarich: per "METHODE pad" een status en een antwoord.
class NepDawarich implements HttpClientAdapter {
  final antwoorden = <String, (int, Object?)>{};
  final verzoeken = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    verzoeken.add(options);
    final (status, body) =
        antwoorden['${options.method} ${options.uri.path}'] ?? (404, null);
    return ResponseBody.fromString(
      body is String ? body : jsonEncode(body ?? {}),
      status,
      headers: {
        Headers.contentTypeHeader: [
          body is String ? 'text/html' : Headers.jsonContentType,
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const ingelogd = {
  'user_id': 1,
  'email': 'ik@thuis.nl',
  'api_key': 'geheim123',
  'status': 'active',
};

const mij = {
  'user': {'email': 'ik@thuis.nl'},
  'features': {'family': true, 'reverse_geocoding': false},
};

const mine = {
  'lapsed': false,
  'family': {'name': 'Droog'},
  'me': {
    'user_id': 1,
    'owner': true,
    'sharing': {
      'enabled': true,
      'duration': '6h',
      'expires_at': '2026-09-24T18:00:00Z',
    },
  },
  'members': [
    {'user_id': 1, 'email': 'ik@thuis.nl'},
    {'user_id': 2, 'email': 'partner@thuis.nl'},
  ],
};

const locaties = {
  'locations': [
    {
      'user_id': 1,
      'email': 'ik@thuis.nl',
      'email_initial': 'I',
      'latitude': 52.1,
      'longitude': 5.1,
      'timestamp': 1790000000,
    },
    {
      'user_id': 2,
      'email': 'partner@thuis.nl',
      'email_initial': 'P',
      'latitude': '52.3',
      'longitude': '5.2',
      'timestamp': 1790000100,
      'battery': 81,
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NepDawarich nep;
  late DawarichService dienst;

  setUp(() {
    nep = NepDawarich();
    dienst = DawarichService(Dio()..httpClientAdapter = nep);
  });

  group('de dienst', () {
    test('een adres wordt een basis zonder / aan het eind', () {
      expect(
        DawarichService.normaliseer(' dawarich.test/ '),
        'https://dawarich.test',
      );
      expect(
        DawarichService.normaliseer('http://10.0.0.2:3000'),
        'http://10.0.0.2:3000',
      );
      expect(DawarichService.normaliseer(''), isNull);
      expect(DawarichService.normaliseer('ftp://x'), isNull);
    });

    test('inloggen geeft de API-sleutel', () async {
      nep.antwoorden['POST /api/v1/auth/login'] = (200, ingelogd);
      final uitslag = await dienst.login(server, 'ik@thuis.nl', 'ww');
      expect(uitslag, isA<DawarichIngelogd>());
      uitslag as DawarichIngelogd;
      expect(uitslag.sleutel, 'geheim123');
      expect(uitslag.account.userId, 1);
      expect(nep.verzoeken.single.data, {
        'email': 'ik@thuis.nl',
        'password': 'ww',
      });
    });

    test('met tweestapsverificatie eerst de code', () async {
      nep.antwoorden['POST /api/v1/auth/login'] = (
        202,
        {'two_factor_required': true, 'challenge_token': 'uitdaging'},
      );
      nep.antwoorden['POST /api/v1/auth/otp_challenge'] = (200, ingelogd);
      final uitslag = await dienst.login(server, 'ik@thuis.nl', 'ww');
      expect((uitslag as DawarichTweeStap).token, 'uitdaging');
      final klaar = await dienst.otp(server, 'uitdaging', ' 123456 ');
      expect(klaar.sleutel, 'geheim123');
      expect(nep.verzoeken.last.data, {
        'challenge_token': 'uitdaging',
        'otp_code': '123456',
      });
    });

    test('fouten krijgen een soort', () async {
      Future<DawarichFoutSoort?> soort(Future<void> Function() doe) async {
        try {
          await doe();
        } on DawarichFout catch (fout) {
          return fout.soort;
        }
        return null;
      }

      nep.antwoorden['POST /api/v1/auth/login'] = (
        401,
        {'error': 'auth_failed'},
      );
      expect(
        await soort(() => dienst.login(server, 'a', 'b')),
        DawarichFoutSoort.inlog,
      );
      nep.antwoorden['POST /api/v1/auth/login'] = (
        403,
        {'error': 'auth_failed'},
      );
      expect(
        await soort(() => dienst.login(server, 'a', 'b')),
        DawarichFoutSoort.wachtwoordUit,
      );
      expect(
        await soort(() => dienst.familie(server, 'k')),
        DawarichFoutSoort.geenFamilie,
      );
      nep.antwoorden['GET /api/v1/families/mine'] = (
        403,
        {'error': 'family_plan_required'},
      );
      expect(
        await soort(() => dienst.familie(server, 'k')),
        DawarichFoutSoort.geenAbonnement,
      );
      // Een webpagina in plaats van JSON: geen Dawarich op dit adres.
      nep.antwoorden['GET /api/v1/users/me'] = (200, '<html></html>');
      expect(
        await soort(() => dienst.controleerSleutel(server, 'k')),
        DawarichFoutSoort.verbinding,
      );
    });

    test('familie en locaties, met de sleutel als Bearer', () async {
      nep.antwoorden['GET /api/v1/families/mine'] = (200, mine);
      nep.antwoorden['GET /api/v1/families/locations'] = (200, locaties);
      final status = await dienst.familie(server, 'geheim123');
      expect(status.naam, 'Droog');
      expect(status.delenAan, isTrue);
      expect(status.duur, DeelDuur.uur6);
      expect(status.verlooptOm, DateTime.utc(2026, 9, 24, 18).toLocal());
      expect(status.leden, ['partner@thuis.nl']);

      final lijst = await dienst.locaties(server, 'geheim123');
      expect(lijst, hasLength(2));
      expect(lijst[1].initiaal, 'P');
      expect(lijst[1].punt.latitude, 52.3);
      expect(lijst[1].batterij, 81);
      expect(nep.verzoeken.last.headers['Authorization'], 'Bearer geheim123');
    });

    test('delen met een duur', () async {
      nep.antwoorden['PATCH /api/v1/families/sharing'] = (
        200,
        {'success': true},
      );
      await dienst.zetDelen(server, 'k', aan: true, duur: DeelDuur.uur1);
      expect(nep.verzoeken.last.data, {'enabled': true, 'duration': '1h'});
      await dienst.zetDelen(server, 'k', aan: false);
      expect(nep.verzoeken.last.data, {'enabled': false});
    });
  });

  group('het account', () {
    late ProviderContainer c;
    late GeheugenGeheimOpslag sleutels;

    setUp(() {
      sleutels = GeheugenGeheimOpslag();
      nep.antwoorden['POST /api/v1/auth/login'] = (200, ingelogd);
      nep.antwoorden['GET /api/v1/users/me'] = (200, mij);
      nep.antwoorden['GET /api/v1/families/mine'] = (200, mine);
      nep.antwoorden['GET /api/v1/families/locations'] = (200, locaties);
      c = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(Dio()..httpClientAdapter = nep),
          dawarichGeheimProvider.overrideWithValue(sleutels),
          geheimOpslagProvider.overrideWithValue(GeheugenGeheimOpslag()),
        ],
      );
    });

    tearDown(() => c.dispose());

    test('inloggen bewaart de sleutel veilig', () async {
      await c
          .read(dawarichProvider.notifier)
          .inloggen(server, ' ik@thuis.nl ', 'ww');
      expect(c.read(dawarichProvider)?.email, 'ik@thuis.nl');
      expect(c.read(dawarichProvider)?.familie, isTrue);
      expect(sleutels.geheim, 'geheim123');
      expect(c.read(dawarichProvider.notifier).sleutel, 'geheim123');
    });

    test(
      'delen onderweg vult de deel-instellingen; uitloggen zet ze uit',
      () async {
        final notifier = c.read(dawarichProvider.notifier);
        await notifier.inloggen(server, 'ik@thuis.nl', 'ww');
        await notifier.zetDelenOnderweg(true);
        final deel = c.read(deelInstellingenProvider);
        expect(deel.aan, isTrue);
        expect(deel.sjabloon, DeelSjabloon.dawarich);
        expect(deel.url, '$server/api/v1/points');
        expect(deel.inlog, DeelInlog.bearer);
        expect(deel.geheim, 'geheim123');
        expect(deeltViaDawarich(deel, c.read(dawarichProvider)), isTrue);

        await notifier.uitloggen();
        expect(c.read(dawarichProvider), isNull);
        expect(c.read(deelInstellingenProvider).aan, isFalse);
        expect(c.read(deelInstellingenProvider).geheim, isEmpty);
        expect(sleutels.geheim, isEmpty);
      },
    );

    test('op de kaart alleen de anderen', () async {
      final notifier = c.read(dawarichProvider.notifier);
      await notifier.inloggen(server, 'ik@thuis.nl', 'ww');
      c.listen(familieLocatiesProvider, (_, _) {});
      expect(c.read(familieLocatiesProvider), isEmpty);
      await notifier.zetToonFamilie(true);
      await c.read(familieLocatiesProvider.notifier).haal();
      final familie = c.read(familieLocatiesProvider);
      expect(familie.single.email, 'partner@thuis.nl');

      await notifier.zetToonFamilie(false);
      expect(c.read(familieLocatiesProvider), isEmpty);
    });

    test('volgen haalt meteen en daarna elke 5 seconden', () async {
      final notifier = c.read(dawarichProvider.notifier);
      await notifier.inloggen(server, 'ik@thuis.nl', 'ww');
      await notifier.zetToonFamilie(true);
      c.listen(familieLocatiesProvider, (_, _) {});
      await c.read(familieLocatiesProvider.notifier).haal();
      int opgehaald() => nep.verzoeken
          .where((v) => v.uri.path == '/api/v1/families/locations')
          .length;
      final voor = opgehaald();
      c.read(gevolgdLidProvider.notifier).volg(2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(opgehaald(), voor + 1);
      expect(c.read(familieLocatiesProvider).single.userId, 2);
      c.read(gevolgdLidProvider.notifier).stop();
      expect(c.read(gevolgdLidProvider), isNull);
    });

    test('familie delen zet het en haalt de status opnieuw', () async {
      nep.antwoorden['PATCH /api/v1/families/sharing'] = (
        200,
        {'success': true},
      );
      await c
          .read(dawarichProvider.notifier)
          .inloggen(server, 'ik@thuis.nl', 'ww');
      expect((await c.read(familieProvider.future))?.delenAan, isTrue);
      await c.read(familieProvider.notifier).zetDelen(false);
      expect(nep.verzoeken.where((v) => v.method == 'PATCH'), hasLength(1));
    });
  });

  test('geleden in minuten, uren of dagen', () async {
    final l = await AppLocalizations.delegate.load(const Locale('nl'));
    expect(geleden(l, const Duration(seconds: 20)), 'zojuist');
    expect(geleden(l, const Duration(minutes: 1)), '1 minuut geleden');
    expect(geleden(l, const Duration(minutes: 59)), '59 minuten geleden');
    expect(geleden(l, const Duration(minutes: 60)), '1 uur geleden');
    expect(geleden(l, const Duration(hours: 5, minutes: 50)), '5 uur geleden');
    expect(geleden(l, const Duration(hours: 24)), '1 dag geleden');
    expect(geleden(l, const Duration(days: 3)), '3 dagen geleden');
    // Een klok die iets voorloopt: niet "-1 minuten".
    expect(geleden(l, const Duration(seconds: -30)), 'zojuist');
  });

  group('het scherm', () {
    Future<ProviderContainer> toon(WidgetTester tester) async {
      nep.antwoorden['POST /api/v1/auth/login'] = (200, ingelogd);
      nep.antwoorden['GET /api/v1/users/me'] = (200, mij);
      nep.antwoorden['GET /api/v1/families/mine'] = (200, mine);
      final c = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(Dio()..httpClientAdapter = nep),
          dawarichGeheimProvider.overrideWithValue(GeheugenGeheimOpslag()),
          geheimOpslagProvider.overrideWithValue(GeheugenGeheimOpslag()),
        ],
      );
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            locale: const Locale('nl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const InstellingenScreen(categorie: 'dawarich'),
          ),
        ),
      );
      return c;
    }

    testWidgets('inloggen en dan de schakelaars', (tester) async {
      await toon(tester);
      expect(find.text('Inloggen'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Server'),
        'dawarich.test',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'ik@thuis.nl',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Wachtwoord'),
        'ww',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Inloggen'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Ingelogd als ik@thuis.nl'), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Locatie delen met familie'), findsOneWidget);
      expect(find.text('Familieleden op de kaart'), findsOneWidget);
      expect(find.text('Locatie delen tijdens navigeren'), findsOneWidget);
    });

    testWidgets('met een sleutel, en een fout', (tester) async {
      await toon(tester);
      nep.antwoorden['GET /api/v1/users/me'] = (401, {'error': 'x'});
      await tester.tap(find.text('API-sleutel').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Server'),
        'dawarich.test',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'API-sleutel'),
        'fout',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Inloggen'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('Onjuiste gegevens.'), findsOneWidget);
    });
  });
}
