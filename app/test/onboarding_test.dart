import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/providers/services.dart';
import 'package:homemaps/providers/settings.dart';
import 'package:homemaps/screens/onboarding.dart';

/// A HomeMaps server where everything works.
class WorkingServer implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({'ok': true}),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  test('a new installation starts with the welcome, an old one not', () async {
    final dir = await Directory.systemTemp.createTemp('onboarding');
    addTearDown(() => dir.delete(recursive: true));
    Hive.init(dir.path);
    final box = await Hive.openBox<dynamic>('settings');
    addTearDown(box.close);
    bool setupDone() {
      final c = ProviderContainer(
        overrides: [settingsBoxProvider.overrideWithValue(box)],
      );
      addTearDown(c.dispose);
      return c.read(settingsProvider).setupDone;
    }

    expect(setupDone(), isFalse);
    // An installation from before the welcome existed.
    await box.put('style', 'osm-bright');
    expect(setupDone(), isTrue);
    await box.put('setupDone', false);
    expect(setupDone(), isFalse);
  });

  test('a shared route or a simulation skips the welcome', () {
    bool skipped(String url) => OnboardingScreen.skippedFor(Uri.parse(url));
    expect(skipped('https://maps.home.nl/?to=52.1,5.1'), isTrue);
    expect(skipped('https://maps.home.nl/?simulate=52,5&speed=15'), isTrue);
    expect(skipped('https://maps.home.nl/'), isFalse);
    expect(skipped('https://maps.home.nl/settings/about'), isFalse);
  });

  testWidgets('welcome, server, then Dawarich and sharing can be skipped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(
          Dio()..httpClientAdapter = WorkingServer(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final settings = container.read(settingsProvider.notifier);
    settings.modify(settings.state.copyWith(setupDone: false));
    var left = false;
    OnboardingScreen.leave = (_) => left = true;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('nl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welkom bij HomeMaps'), findsOneWidget);

    await tester.tap(find.text('Aan de slag'));
    await tester.pumpAndSettle();
    expect(find.text('Stap 1 van 3'), findsOneWidget);
    FilledButton next() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Volgende'),
    );
    // No server yet: no further.
    expect(next().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'maps.home.nl');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      find.text('De server werkt: kaart, zoeken en routes'),
      findsOneWidget,
    );
    // Saved as soon as it works, without the button.
    expect(container.read(settingsProvider).server, 'https://maps.home.nl');
    expect(next().onPressed, isNotNull);

    await tester.tap(find.text('Volgende'));
    await tester.pumpAndSettle();
    expect(find.text('Stap 2 van 3'), findsOneWidget);
    expect(find.text('Dawarich'), findsWidgets);

    // Back and forth keeps the server.
    await tester.tap(find.text('Terug'));
    await tester.pumpAndSettle();
    expect(find.text('https://maps.home.nl'), findsOneWidget);
    await tester.tap(find.text('Volgende'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Overslaan'));
    await tester.pumpAndSettle();
    expect(find.text('Stap 3 van 3'), findsOneWidget);
    expect(container.read(settingsProvider).setupDone, isFalse);

    await tester.tap(find.text('Overslaan en beginnen'));
    expect(container.read(settingsProvider).setupDone, isTrue);
    expect(left, isTrue);
  });
}
