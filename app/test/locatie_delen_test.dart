import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:homemaps/models/locatie_delen.dart';
import 'package:homemaps/providers/diensten.dart';
import 'package:homemaps/providers/locatie.dart';
import 'package:homemaps/providers/locatie_delen.dart';
import 'package:homemaps/screens/locatie_delen_screen.dart';
import 'package:homemaps/services/locatie_deler.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'hulp/nep_bron.dart';

const punt = DeelPunt(
  lat: 52.09,
  lon: 5.12,
  tst: 1790000000,
  acc: 4.6,
  vel: 27.77,
  bear: 88.5,
);

DeelInstellingen met(DeelSjabloon sjabloon, {String url = 'https://s.nl/x'}) =>
    DeelInstellingen(aan: true, url: url).metSjabloon(sjabloon);

/// Doet alsof hij stuurt; de test bepaalt het antwoord.
class NepVerzender implements DeelVerzender {
  final verzoeken = <DeelVerzoek>[];
  int status = 200;
  bool offline = false;

  @override
  Future<int> stuur(DeelVerzoek verzoek) async {
    if (offline) throw const SocketException('geen netwerk');
    verzoeken.add(verzoek);
    return status;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('het verzoek, zoals Colota', () {
    test('OwnTracks en Dawarich: cog, _type en tid', () {
      final v = bouwVerzoek(met(DeelSjabloon.owntracks), [punt]);
      expect(v.methode, DeelMethode.post);
      expect(v.body, {
        'lat': 52.09,
        'lon': 5.12,
        'acc': 5,
        'vel': 27.8,
        'tst': 1790000000,
        'cog': 88.5,
        '_type': 'location',
        'tid': 'HM',
      });
      final d = bouwVerzoek(met(DeelSjabloon.dawarich), [punt]).body!;
      expect(d['cog'], 88.5);
      expect(d['_type'], 'location');
      expect(d.containsKey('tid'), isFalse);
    });

    test('PhoneTrack: speed, timestamp en bearing', () {
      final b = bouwVerzoek(met(DeelSjabloon.phonetrack), [punt]).body!;
      expect(b['speed'], 27.8);
      expect(b['timestamp'], 1790000000);
      expect(b['bearing'], 88.5);
      expect(b['useragent'], 'HomeMaps');
      expect(b.containsKey('vel'), isFalse);
    });

    test('Traccar: OsmAnd-query bij GET, JSON bij POST', () {
      final get = bouwVerzoek(
        met(DeelSjabloon.traccar, url: 'http://10.0.0.2:5055/?extra=1'),
        [punt],
      );
      expect(get.methode, DeelMethode.get);
      expect(get.body, isNull);
      expect(get.uri.queryParameters, {
        'extra': '1',
        'lat': '52.09',
        'lon': '5.12',
        'accuracy': '5',
        'speed': '27.8',
        'timestamp': '1790000000',
        'bearing': '88.5',
        'id': 'homemaps',
      });

      final post = bouwVerzoek(
        met(DeelSjabloon.traccar).kopie(methode: DeelMethode.post),
        [punt],
      );
      expect(post.body, {
        'location': {
          'timestamp': '2026-09-21T14:13:20Z',
          'coords': {
            'latitude': 52.09,
            'longitude': 5.12,
            'accuracy': 4.6,
            'speed': 27.77,
            'heading': 88.5,
          },
        },
        'device_id': 'homemaps',
      });
    });

    test('Overland: alle punten in één GeoJSON-envelop', () {
      final v = bouwVerzoek(met(DeelSjabloon.overland), [punt, punt]);
      final body = v.body!;
      expect(body['device_id'], 'homemaps');
      final locaties = body['locations']! as List;
      expect(locaties, hasLength(2));
      expect(locaties.first, {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [5.12, 52.09],
        },
        'properties': {
          'timestamp': '2026-09-21T14:13:20Z',
          'horizontal_accuracy': 5,
          'speed': 27.77,
          'course': 88.5,
        },
      });
      expect(puntenPerVerzoek(met(DeelSjabloon.overland)), 100);
      expect(puntenPerVerzoek(met(DeelSjabloon.owntracks)), 1);
    });

    test('aangepast: eigen veldnamen, en inloggen', () {
      final eigen = met(DeelSjabloon.aangepast).kopie(
        veldnamen: {'lat': 'latitude', 'lon': 'longitude', 'vel': ''},
        extraVelden: {'apparaat': 'auto'},
        inlog: DeelInlog.basic,
        gebruiker: 'jan',
        geheim: 'geheim',
      );
      final v = bouwVerzoek(eigen, [punt]);
      expect(v.body!['latitude'], 52.09);
      expect(v.body!['vel'], 27.8);
      expect(v.body!['apparaat'], 'auto');
      expect(
        v.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('jan:geheim'))}',
      );
      final token = bouwVerzoek(
        eigen.kopie(inlog: DeelInlog.bearer, geheim: 'abc'),
        [punt],
      );
      expect(token.headers['Authorization'], 'Bearer abc');
    });

    test('instellingen over een herstart, zonder het geheim', () {
      final opgeslagen = DeelInstellingen.vanMap(
        met(DeelSjabloon.traccar).kopie(geheim: 'x', interval: 30).naarMap(),
      );
      expect(opgeslagen.sjabloon, DeelSjabloon.traccar);
      expect(opgeslagen.methode, DeelMethode.get);
      expect(opgeslagen.interval, 30);
      expect(opgeslagen.extraVelden, {'id': 'homemaps'});
      expect(opgeslagen.geheim, '');
    });
  });

  group('versturen tijdens het navigeren', () {
    late ProviderContainer c;
    late NepBron bron;
    late NepVerzender verzender;

    ProviderContainer maak({DeelWachtrij? wachtrij}) {
      final container = ProviderContainer(
        overrides: [
          locatieBronProvider.overrideWithValue(bron),
          deelVerzenderProvider.overrideWithValue(verzender),
          geheimOpslagProvider.overrideWithValue(GeheugenGeheimOpslag()),
          if (wachtrij != null)
            deelWachtrijProvider.overrideWithValue(wachtrij),
        ],
      );
      addTearDown(container.dispose);
      container.read(locatieDelerProvider);
      return container;
    }

    Future<void> rij(double lat, DateTime tijd) async {
      bron.fixes.add(
        LocatieFix(
          punt: LatLng(lat, 5.0),
          tijd: tijd,
          nauwkeurigheid: 5,
          snelheid: 20,
          koers: 0,
        ),
      );
      await pumpEventQueue();
    }

    setUp(() async {
      bron = NepBron(Toestemming.ja);
      verzender = NepVerzender();
      c = maak();
      await c
          .read(deelInstellingenProvider.notifier)
          .wijzig(met(DeelSjabloon.owntracks));
      final wacht = c.read(locatieProvider.notifier).zetAan();
      await pumpEventQueue();
      bron.fixes.add(fix(52.0));
      await wacht;
      await pumpEventQueue();
    });

    final t0 = DateTime(2026, 9, 23, 12);

    test('niets zonder navigatie, of als het uit staat', () async {
      await rij(52.001, t0);
      expect(verzender.verzoeken, isEmpty);

      await c
          .read(deelInstellingenProvider.notifier)
          .wijzig(met(DeelSjabloon.owntracks).kopie(aan: false));
      c.read(onderwegProvider.notifier).zet(true);
      await rij(52.002, t0);
      expect(verzender.verzoeken, isEmpty);
    });

    test('na het interval of de afstand, niet bij elke fix', () async {
      c.read(onderwegProvider.notifier).zet(true);
      await rij(52.0, t0);
      // 2 s later, 11 m verder: te vroeg en te dichtbij.
      await rij(52.0001, t0.add(const Duration(seconds: 2)));
      // 4 s later, 33 m verder: ver genoeg.
      await rij(52.0003, t0.add(const Duration(seconds: 4)));
      // 14 s later, stilstaand: lang genoeg.
      await rij(52.0003, t0.add(const Duration(seconds: 14)));
      expect(verzender.verzoeken, hasLength(3));
      expect(c.read(locatieDelerProvider).inWachtrij, 0);
      expect(c.read(locatieDelerProvider).laatstVerstuurd, isNotNull);
    });

    test('zonder netwerk in de wachtrij, daarna in volgorde', () async {
      c.read(onderwegProvider.notifier).zet(true);
      verzender.offline = true;
      await rij(52.0, t0);
      expect(c.read(locatieDelerProvider).inWachtrij, 1);
      expect(c.read(locatieDelerProvider).fout, contains('geen netwerk'));
      await rij(52.001, t0.add(const Duration(seconds: 20)));
      // Tijdens het wachten niet steeds opnieuw proberen.
      expect(c.read(locatieDelerProvider).inWachtrij, 2);

      // Netwerk terug; de wachttijd van de deler slaan we over.
      verzender.offline = false;
      await c
          .read(deelInstellingenProvider.notifier)
          .wijzig(met(DeelSjabloon.owntracks).kopie(interval: 11));
      await pumpEventQueue();
      expect(c.read(locatieDelerProvider).inWachtrij, 0);
      expect(
        [for (final v in verzender.verzoeken) v.body!['lat']],
        [52.0, 52.001],
      );
    });

    test('een 401 is de instelling: stoppen, en de punten bewaren', () async {
      c.read(onderwegProvider.notifier).zet(true);
      verzender.status = 401;
      await rij(52.0, t0);
      await rij(52.001, t0.add(const Duration(seconds: 20)));
      final status = c.read(locatieDelerProvider);
      expect(status.gestopt, isTrue);
      expect(status.fout, 'HTTP 401');
      expect(status.inWachtrij, 2);
      // Alleen de eerste poging; daarna niet meer tot de instelling verandert.
      expect(verzender.verzoeken, hasLength(1));
    });

    test('de wachtrij over een herstart', () async {
      final map = await Directory.systemTemp.createTemp('wachtrij');
      addTearDown(() => map.delete(recursive: true));
      Hive.init(map.path);
      final doos = await Hive.openBox<dynamic>('deelWachtrij');
      addTearDown(doos.close);
      final wachtrij = DeelWachtrij(doos);
      await wachtrij.voegToe(punt);
      await wachtrij.voegToe(const DeelPunt(lat: 1, lon: 2, tst: 3));
      final opnieuw = DeelWachtrij(doos);
      expect(opnieuw.lengte, 2);
      expect(opnieuw.eerste(1).single.lat, 52.09);
      await opnieuw.haalWeg(1);
      expect(opnieuw.eerste(5).single.lat, 1);
    });

    test('niet meer dan het maximum', () async {
      final wachtrij = DeelWachtrij();
      for (var i = 0; i < DeelWachtrij.maximum + 3; i++) {
        await wachtrij.voegToe(DeelPunt(lat: i.toDouble(), lon: 0, tst: i));
      }
      expect(wachtrij.lengte, DeelWachtrij.maximum);
      // De oudste vallen weg.
      expect(wachtrij.eerste(1).single.lat, 3);
    });
  });

  testWidgets(
    'scherm: een server kiezen vult de vaste velden en het voorbeeld',
    (tester) async {
      tester.view.physicalSize = const Size(800, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final opslag = GeheugenGeheimOpslag();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            geheimOpslagProvider.overrideWithValue(opslag),
            deelVerzenderProvider.overrideWithValue(NepVerzender()),
          ],
          child: MaterialApp(
            locale: const Locale('nl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LocatieDelenScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Standaard OwnTracks.
      expect(find.text('_type=location\ntid=HM'), findsOneWidget);

      await tester.tap(find.text('Traccar'));
      await tester.pumpAndSettle();
      expect(find.text('id=homemaps'), findsOneWidget);
      expect(find.text('POST'), findsOneWidget);

      // Aanzetten zonder adres mag niet.
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        find.text('Vul een adres in dat met http:// of https:// begint.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Adres (URL)'),
        'http://10.0.0.2:5055',
      );
      await tester.pumpAndSettle();
      // Het voorbeeld: een OsmAnd-GET.
      expect(find.textContaining('GET http://10.0.0.2:5055?'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LocatieDelenScreen)),
      );
      final bewaard = container.read(deelInstellingenProvider);
      expect(bewaard.aan, isTrue);
      expect(bewaard.sjabloon, DeelSjabloon.traccar);
      expect(bewaard.url, 'http://10.0.0.2:5055');
    },
  );
}
