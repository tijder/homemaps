import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/models/dawarich.dart';
import 'package:homemaps/models/location_sharing.dart';
import 'package:homemaps/providers/dawarich.dart';
import 'package:homemaps/providers/services.dart';
import 'package:homemaps/providers/location_sharing.dart';
import 'package:homemaps/screens/settings/dawarich.dart';
import 'package:homemaps/screens/settings/dawarich_website.dart';
import 'package:homemaps/screens/settings/settings_screen.dart';
import 'package:homemaps/services/dawarich_service.dart';
import 'package:homemaps/utils/formatting.dart';

const server = 'https://dawarich.test';

/// Plays Dawarich: per "METHOD path" a status and a response.
class FakeDawarich implements HttpClientAdapter {
  final responses = <String, (int, Object?)>{};
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) =
        responses['${options.method} ${options.uri.path}'] ?? (404, null);
    return ResponseBody.fromString(
      body is String ? body : jsonEncode(body ?? {}),
      status,
      headers: {
        Headers.contentTypeHeader: [
          body is String ? 'text/html' : Headers.jsonContentType,
        ],
        'x-dawarich-version': ['1.15.2'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const signedIn = {
  'user_id': 1,
  'email': 'me@home.nl',
  'api_key': 'secret123',
  'status': 'active',
};

const meJson = {
  'user': {'email': 'me@home.nl'},
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
    {'user_id': 1, 'email': 'me@home.nl'},
    {'user_id': 2, 'email': 'partner@home.nl'},
  ],
};

const locations = {
  'locations': [
    {
      'user_id': 1,
      'email': 'me@home.nl',
      'email_initial': 'M',
      'latitude': 52.1,
      'longitude': 5.1,
      'timestamp': 1790000000,
    },
    {
      'user_id': 2,
      'email': 'partner@home.nl',
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

  late FakeDawarich fake;
  late DawarichService service;

  setUp(() {
    fake = FakeDawarich();
    service = DawarichService(Dio()..httpClientAdapter = fake);
  });

  group('the service', () {
    test('an address becomes a base without a trailing /', () {
      expect(
        DawarichService.normalize(' dawarich.test/ '),
        'https://dawarich.test',
      );
      expect(
        DawarichService.normalize('http://10.0.0.2:3000'),
        'http://10.0.0.2:3000',
      );
      expect(DawarichService.normalize(''), isNull);
      expect(DawarichService.normalize('ftp://x'), isNull);
    });

    test('signing in returns the API key', () async {
      fake.responses['POST /api/v1/auth/login'] = (200, signedIn);
      final outcome = await service.login(server, 'me@home.nl', 'pw');
      expect(outcome, isA<DawarichSignedIn>());
      outcome as DawarichSignedIn;
      expect(outcome.key, 'secret123');
      expect(outcome.account.userId, 1);
      expect(fake.requests.single.data, {
        'email': 'me@home.nl',
        'password': 'pw',
      });
    });

    test('with two-factor authentication the code first', () async {
      fake.responses['POST /api/v1/auth/login'] = (
        202,
        {'two_factor_required': true, 'challenge_token': 'challenge'},
      );
      fake.responses['POST /api/v1/auth/otp_challenge'] = (200, signedIn);
      final outcome = await service.login(server, 'me@home.nl', 'pw');
      expect((outcome as DawarichTwoFactor).token, 'challenge');
      final done = await service.otp(server, 'challenge', ' 123456 ');
      expect(done.key, 'secret123');
      expect(fake.requests.last.data, {
        'challenge_token': 'challenge',
        'otp_code': '123456',
      });
    });

    test('errors get a kind', () async {
      Future<DawarichErrorKind?> kind(Future<void> Function() run) async {
        try {
          await run();
        } on DawarichError catch (error) {
          return error.kind;
        }
        return null;
      }

      fake.responses['POST /api/v1/auth/login'] = (
        401,
        {'error': 'auth_failed'},
      );
      expect(
        await kind(() => service.login(server, 'a', 'b')),
        DawarichErrorKind.auth,
      );
      fake.responses['POST /api/v1/auth/login'] = (
        403,
        {'error': 'auth_failed'},
      );
      expect(
        await kind(() => service.login(server, 'a', 'b')),
        DawarichErrorKind.passwordDisabled,
      );
      expect(
        await kind(() => service.family(server, 'k')),
        DawarichErrorKind.noFamily,
      );
      fake.responses['GET /api/v1/families/mine'] = (
        403,
        {'error': 'family_plan_required'},
      );
      expect(
        await kind(() => service.family(server, 'k')),
        DawarichErrorKind.noSubscription,
      );
      // A web page instead of JSON: no Dawarich at this address.
      fake.responses['GET /api/v1/users/me'] = (200, '<html></html>');
      expect(
        await kind(() => service.checkKey(server, 'k')),
        DawarichErrorKind.notDawarich,
      );
    });

    test('connecting: health and the version, without signing in', () async {
      fake.responses['GET /api/v1/health'] = (200, {'status': 'ok'});
      expect((await service.connect(server)).version, '1.15.2');
      expect(fake.requests.last.headers['Authorization'], isNull);

      // A login proxy returns its own page.
      fake.responses['GET /api/v1/health'] = (200, '<html>Authelia</html>');
      await expectLater(
        service.connect(server),
        throwsA(
          isA<DawarichError>().having(
            (f) => f.kind,
            'kind',
            DawarichErrorKind.notDawarich,
          ),
        ),
      );
      // Nothing at this address.
      fake.responses.remove('GET /api/v1/health');
      await expectLater(service.connect(server), throwsA(isA<DawarichError>()));
    });

    test('family and locations, with the key as Bearer', () async {
      fake.responses['GET /api/v1/families/mine'] = (200, mine);
      fake.responses['GET /api/v1/families/locations'] = (200, locations);
      final status = await service.family(server, 'secret123');
      expect(status.label, 'Droog');
      expect(status.sharingEnabled, isTrue);
      expect(status.duration, ShareDuration.hour6);
      expect(status.expiresAt, DateTime.utc(2026, 9, 24, 18).toLocal());
      expect(status.members, ['partner@home.nl']);

      final list = await service.locations(server, 'secret123');
      expect(list, hasLength(2));
      expect(list[1].initial, 'P');
      expect(list[1].point.latitude, 52.3);
      expect(list[1].battery, 81);
      expect(fake.requests.last.headers['Authorization'], 'Bearer secret123');
    });

    test('the key from the redirect after the website', () {
      String jwt(Object content) => [
        'eyJhbGciOiJIUzI1NiJ9',
        base64Url.encode(utf8.encode(jsonEncode(content))).replaceAll('=', ''),
        'signature',
      ].join('.');
      final correct = Uri.parse(
        '$server/auth/ios/success?token=${jwt({'api_key': 'k3y', 'exp': 1})}',
      );
      expect(DawarichService.isHandoff(correct), isTrue);
      expect(DawarichService.keyFromHandoff(correct), 'k3y');

      expect(
        DawarichService.isHandoff(Uri.parse('$server/users/sign_in')),
        isFalse,
      );
      expect(
        DawarichService.keyFromHandoff(
          Uri.parse('$server/auth/ios/success?token=${jwt({'exp': 1})}'),
        ),
        isNull,
      );
      expect(
        DawarichService.keyFromHandoff(
          Uri.parse('$server/auth/ios/success?token=not.a.jwt'),
        ),
        isNull,
      );
    });

    test('sharing with a duration', () async {
      fake.responses['PATCH /api/v1/families/sharing'] = (
        200,
        {'success': true},
      );
      await service.setSharing(
        server,
        'k',
        enabled: true,
        duration: ShareDuration.hour1,
      );
      expect(fake.requests.last.data, {'enabled': true, 'duration': '1h'});
      await service.setSharing(server, 'k', enabled: false);
      expect(fake.requests.last.data, {'enabled': false});
    });
  });

  group('the account', () {
    late ProviderContainer c;
    late MemorySecretStore keys;

    setUp(() {
      keys = MemorySecretStore();
      fake.responses['POST /api/v1/auth/login'] = (200, signedIn);
      fake.responses['GET /api/v1/users/me'] = (200, meJson);
      fake.responses['GET /api/v1/families/mine'] = (200, mine);
      fake.responses['GET /api/v1/families/locations'] = (200, locations);
      c = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(Dio()..httpClientAdapter = fake),
          dawarichSecretProvider.overrideWithValue(keys),
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
        ],
      );
    });

    tearDown(() => c.dispose());

    test('signing in stores the key securely', () async {
      await c
          .read(dawarichProvider.notifier)
          .signIn(server, ' me@home.nl ', 'pw');
      expect(c.read(dawarichProvider)?.email, 'me@home.nl');
      expect(c.read(dawarichProvider)?.family, isTrue);
      expect(keys.secret, 'secret123');
      expect(c.read(dawarichProvider.notifier).key, 'secret123');
    });

    test(
      'sharing en route fills the share settings; signing out turns them off',
      () async {
        final notifier = c.read(dawarichProvider.notifier);
        await notifier.signIn(server, 'me@home.nl', 'pw');
        await notifier.setShareEnRoute(true);
        final share = c.read(shareSettingsProvider);
        expect(share.enabled, isTrue);
        expect(share.template, ShareTemplate.dawarich);
        expect(share.url, '$server/api/v1/points');
        expect(share.auth, ShareAuth.bearer);
        expect(share.secret, 'secret123');
        expect(sharesViaDawarich(share, c.read(dawarichProvider)), isTrue);

        await notifier.signOut();
        expect(c.read(dawarichProvider), isNull);
        expect(c.read(shareSettingsProvider).enabled, isFalse);
        expect(c.read(shareSettingsProvider).secret, isEmpty);
        expect(keys.secret, isEmpty);
      },
    );

    test('only the others on the map', () async {
      final notifier = c.read(dawarichProvider.notifier);
      await notifier.signIn(server, 'me@home.nl', 'pw');
      c.listen(familyLocationsProvider, (_, _) {});
      expect(c.read(familyLocationsProvider), isEmpty);
      await notifier.setShowFamily(true);
      await c.read(familyLocationsProvider.notifier).fetch();
      final family = c.read(familyLocationsProvider);
      expect(family.single.email, 'partner@home.nl');

      await notifier.setShowFamily(false);
      expect(c.read(familyLocationsProvider), isEmpty);
    });

    test('following fetches immediately and then every 5 seconds', () async {
      final notifier = c.read(dawarichProvider.notifier);
      await notifier.signIn(server, 'me@home.nl', 'pw');
      await notifier.setShowFamily(true);
      c.listen(familyLocationsProvider, (_, _) {});
      await c.read(familyLocationsProvider.notifier).fetch();
      int fetched() => fake.requests
          .where((v) => v.uri.path == '/api/v1/families/locations')
          .length;
      final before = fetched();
      c.read(followedMemberProvider.notifier).follow(2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fetched(), before + 1);
      expect(c.read(familyLocationsProvider).single.userId, 2);
      c.read(followedMemberProvider.notifier).stop();
      expect(c.read(followedMemberProvider), isNull);
    });

    test('family sharing sets it and fetches the status again', () async {
      fake.responses['PATCH /api/v1/families/sharing'] = (
        200,
        {'success': true},
      );
      await c
          .read(dawarichProvider.notifier)
          .signIn(server, 'me@home.nl', 'pw');
      expect((await c.read(familyProvider.future))?.sharingEnabled, isTrue);
      await c.read(familyProvider.notifier).setSharing(false);
      expect(fake.requests.where((v) => v.method == 'PATCH'), hasLength(1));
    });
  });

  test('sharing that ran out is no longer sharing', () {
    final status = FamilyStatus.fromJson(mine);
    final until = DateTime.utc(2026, 9, 24, 18);
    expect(status.sharingEnabled, isTrue);
    expect(
      status.isSharing(until.subtract(const Duration(minutes: 1))),
      isTrue,
    );
    expect(status.isSharing(until), isFalse);
    // "Always" doesn't run out.
    final always = FamilyStatus.fromJson({
      'me': {
        'sharing': {'enabled': true, 'duration': 'permanent'},
      },
    });
    expect(always.isSharing(DateTime.utc(2100)), isTrue);
  });

  test('ago in minutes, hours or days', () async {
    final l = await AppLocalizations.delegate.load(const Locale('nl'));
    expect(timeAgo(l, const Duration(seconds: 20)), 'zojuist');
    expect(timeAgo(l, const Duration(minutes: 1)), '1 minuut geleden');
    expect(timeAgo(l, const Duration(minutes: 59)), '59 minuten geleden');
    expect(timeAgo(l, const Duration(minutes: 60)), '1 uur geleden');
    expect(timeAgo(l, const Duration(hours: 5, minutes: 50)), '5 uur geleden');
    expect(timeAgo(l, const Duration(hours: 24)), '1 dag geleden');
    expect(timeAgo(l, const Duration(days: 3)), '3 dagen geleden');
    // A clock that runs slightly fast: not "-1 minutes".
    expect(timeAgo(l, const Duration(seconds: -30)), 'zojuist');
  });

  group('the screen', () {
    Future<ProviderContainer> showScreen(WidgetTester tester) async {
      fake.responses['GET /api/v1/health'] = (200, {'status': 'ok'});
      fake.responses['POST /api/v1/auth/login'] = (200, signedIn);
      fake.responses['GET /api/v1/users/me'] = (200, meJson);
      fake.responses['GET /api/v1/families/mine'] = (200, mine);
      final c = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(Dio()..httpClientAdapter = fake),
          dawarichSecretProvider.overrideWithValue(MemorySecretStore()),
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
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
            home: const SettingsScreen(category: 'dawarich'),
          ),
        ),
      );
      return c;
    }

    /// Tap, and give the fake server a moment to respond.
    Future<void> tick(WidgetTester tester, Finder what) async {
      await tester.runAsync(() async {
        await tester.tap(what);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> connect(WidgetTester tester) async {
      await tester.enterText(
        find.widgetWithText(TextField, 'Server'),
        'dawarich.test',
      );
      await tick(tester, find.text('Verbinden'));
    }

    testWidgets('first the server, then sign in, only then the settings', (
      tester,
    ) async {
      await showScreen(tester);
      // Step 1: only the server.
      expect(find.widgetWithText(TextField, 'E-mail'), findsNothing);
      expect(find.text('Locatie delen met familie'), findsNothing);
      await connect(tester);

      // Step 2: connected, now sign in.
      expect(find.text('dawarich.test'), findsOneWidget);
      expect(find.text('Verbonden · Dawarich 1.15.2'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'me@home.nl',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Wachtwoord'),
        'pw',
      );
      await tick(tester, find.widgetWithText(FilledButton, 'Inloggen'));

      expect(find.text('me@home.nl'), findsOneWidget);
      expect(
        find.text('dawarich.test · Verbonden · Dawarich 1.15.2'),
        findsOneWidget,
      );
      expect(find.text('Locatie delen met familie'), findsOneWidget);
      expect(find.text('Familieleden op de kaart'), findsOneWidget);
      expect(find.text('Locatie delen tijdens navigeren'), findsOneWidget);
    });

    testWidgets('no Dawarich at the address: a message, no step 2', (
      tester,
    ) async {
      await showScreen(tester);
      fake.responses['GET /api/v1/health'] = (200, '<html>Authelia</html>');
      await connect(tester);
      expect(find.textContaining('antwoordt geen Dawarich'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'E-mail'), findsNothing);
    });

    testWidgets('via the website: the key from the WebView', (tester) async {
      String? opened;
      DawarichSettings.openWebsite = (_, server) async {
        opened = server;
        return 'secret123';
      };
      addTearDown(
        () => DawarichSettings.openWebsite = DawarichWebsiteLogin.open,
      );
      final c = await showScreen(tester);
      await connect(tester);
      await tick(tester, find.text('Via de Dawarich-website'));
      expect(opened, server);
      expect(c.read(dawarichProvider.notifier).key, 'secret123');
      expect(find.text('Locatie delen met familie'), findsOneWidget);
    });

    testWidgets('with a key, and an error', (tester) async {
      await showScreen(tester);
      await connect(tester);
      fake.responses['GET /api/v1/users/me'] = (401, {'error': 'x'});
      await tester.tap(find.text('Met een API-sleutel'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'API-sleutel'),
        'wrong',
      );
      await tick(tester, find.widgetWithText(FilledButton, 'Inloggen').last);
      expect(find.text('Onjuiste gegevens.'), findsOneWidget);
    });

    testWidgets('key expired: only sign in again, server filled in', (
      tester,
    ) async {
      final c = await showScreen(tester);
      await tester.runAsync(
        () => c
            .read(dawarichProvider.notifier)
            .signIn(server, 'me@home.nl', 'pw'),
      );
      fake.responses['GET /api/v1/users/me'] = (401, {'error': 'x'});
      c.invalidate(dawarichConnectionProvider);
      await tick(tester, find.byType(Scaffold).first);
      expect(find.textContaining('Sessie verlopen'), findsOneWidget);
      expect(find.text('Locatie delen met familie'), findsNothing);

      await tick(tester, find.text('Opnieuw inloggen'));
      expect(c.read(dawarichProvider), isNull);
      expect(find.text(server), findsOneWidget);
    });

    testWidgets('sharing whose time has passed shows as off', (tester) async {
      final c = await showScreen(tester);
      Map<String, dynamic> sharingUntil(DateTime until) => {
        ...mine,
        'me': {
          'user_id': 1,
          'sharing': {
            'enabled': true,
            'duration': '1h',
            'expires_at': until.toUtc().toIso8601String(),
          },
        },
      };
      fake.responses['GET /api/v1/families/mine'] = (
        200,
        sharingUntil(DateTime.now().subtract(const Duration(hours: 1))),
      );
      await tester.runAsync(
        () => c
            .read(dawarichProvider.notifier)
            .signIn(server, 'me@home.nl', 'pw'),
      );
      await tick(tester, find.byType(Scaffold).first);
      expect(find.text('Je familie ziet je locatie niet'), findsOneWidget);
      bool switchOn() => tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Locatie delen met familie'),
          )
          .value;
      expect(switchOn(), isFalse);

      fake.responses['GET /api/v1/families/mine'] = (
        200,
        sharingUntil(DateTime.now().add(const Duration(hours: 1))),
      );
      c.invalidate(familyProvider);
      await tick(tester, find.byType(Scaffold).first);
      expect(find.textContaining('Tot '), findsOneWidget);
      expect(switchOn(), isTrue);

      // Asking again cancels the timer for the end of this one.
      fake.responses['GET /api/v1/families/mine'] = (200, mine);
      c.invalidate(familyProvider);
      await tick(tester, find.byType(Scaffold).first);
    });

    testWidgets('signing out asks first', (tester) async {
      final c = await showScreen(tester);
      await tester.runAsync(
        () => c
            .read(dawarichProvider.notifier)
            .signIn(server, 'me@home.nl', 'pw'),
      );
      await tick(tester, find.byType(Scaffold).first);
      await tester.tap(find.text('Uitloggen'));
      await tester.pumpAndSettle();
      expect(find.text('Uitloggen bij Dawarich?'), findsOneWidget);
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
      expect(c.read(dawarichProvider), isNotNull);

      await tester.tap(find.text('Uitloggen'));
      await tester.pumpAndSettle();
      await tick(tester, find.widgetWithText(FilledButton, 'Uitloggen'));
      expect(c.read(dawarichProvider), isNull);
    });
  });
}
