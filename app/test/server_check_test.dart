import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/providers/services.dart';
import 'package:homemaps/providers/settings.dart';
import 'package:homemaps/screens/settings/server.dart';
import 'package:homemaps/services/server_check.dart';

/// A HomeMaps server: JSON on the paths in [working], an HTML page on the rest.
class FakeServer implements HttpClientAdapter {
  FakeServer(this.working);

  final Set<String> working;
  final hosts = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    hosts.add(options.uri.host);
    final json = working.contains(options.uri.path);
    return ResponseBody.fromString(
      json ? jsonEncode({'ok': true}) : '<html></html>',
      200,
      headers: {
        Headers.contentTypeHeader: [
          json ? Headers.jsonContentType : 'text/html',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const all = {'/tiles/data/v3.json', '/geocode', '/valhalla/status'};

void main() {
  test('an address without scheme gets https', () {
    expect(normalizeServer(' maps.home.nl '), 'https://maps.home.nl');
    expect(normalizeServer('http://10.0.0.2:8080'), 'http://10.0.0.2:8080');
    expect(normalizeServer(''), isNull);
    expect(normalizeServer('ftp://maps.home.nl'), isNull);
    expect(normalizeServer('https://'), isNull);
  });

  test('all parts, some, or none', () async {
    Future<ServerCheck> check(Set<String> working) => checkServer(
      Dio()..httpClientAdapter = FakeServer(working),
      'https://m',
    );
    expect((await check(all)).works, isTrue);
    final partly = await check({'/tiles/data/v3.json', '/geocode'});
    expect(partly.works, isFalse);
    expect(partly.unreachable, isFalse);
    expect(partly.failing, {ServerPart.routes});
    // A web page on every path isn't a HomeMaps server.
    expect((await check({})).unreachable, isTrue);
  });

  testWidgets('says while typing whether the server works', (tester) async {
    final server = FakeServer({'/tiles/data/v3.json', '/geocode'});
    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(Dio()..httpClientAdapter = server),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('nl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ServerSettings()),
        ),
      ),
    );
    expect(find.textContaining('Server controleren'), findsNothing);

    await tester.enterText(find.byType(TextField), 'maps.home.nl');
    // Nothing yet during the pause after typing.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('werkt'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(
      find.text('De server antwoordt, maar niet alles werkt: routes'),
      findsOneWidget,
    );
    expect(server.hosts.toSet(), {'maps.home.nl'});

    server.working.add('/valhalla/status');
    await tester.tap(find.text('Opslaan'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).server, 'https://maps.home.nl');
    expect(find.text('https://maps.home.nl'), findsOneWidget);
    // Saving the address that was just checked doesn't check it again.
    expect(find.textContaining('niet alles werkt'), findsOneWidget);
  });
}
