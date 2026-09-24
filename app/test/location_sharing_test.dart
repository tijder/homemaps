import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:homemaps/models/location_sharing.dart';
import 'package:homemaps/models/profile.dart';
import 'package:homemaps/providers/services.dart';
import 'package:homemaps/providers/settings.dart';
import 'package:homemaps/providers/location.dart';
import 'package:homemaps/providers/location_sharing.dart';
import 'package:homemaps/screens/settings/settings_screen.dart';
import 'package:homemaps/screens/settings/location_sharing.dart';
import 'package:homemaps/services/location_sharer.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'helpers/fake_source.dart';

const point = SharedPoint(
  lat: 52.09,
  lon: 5.12,
  tst: 1790000000,
  acc: 4.6,
  vel: 27.77,
  bear: 88.5,
);

ShareSettings settingsFor(
  ShareTemplate template, {
  String url = 'https://s.nl/x',
}) => ShareSettings(enabled: true, url: url).withTemplate(template);

/// Pretends to send; the test decides the response.
class FakeSender implements ShareSender {
  final requests = <ShareRequest>[];
  int status = 200;
  bool offline = false;

  @override
  Future<int> send(ShareRequest request) async {
    if (offline) throw const SocketException('no network');
    requests.add(request);
    return status;
  }
}

/// A fixed battery, without a plugin.
class FakeBattery implements BatterySource {
  BatteryReading value = (percent: 64, currentState: 'charging');

  @override
  Future<BatteryReading> read() async => value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the request, like Colota', () {
    test('OwnTracks: cog, _type and tid', () {
      final v = buildRequest(settingsFor(ShareTemplate.owntracks), [point]);
      expect(v.method, ShareMethod.post);
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
    });

    test('Dawarich: /api/v1/points, per 100, with everything it stores', () {
      const full = SharedPoint(
        lat: 52.09,
        lon: 5.12,
        tst: 1790000000,
        acc: 4.6,
        alt: 3.4,
        vel: 27.77,
        bear: 88.5,
        vac: 2.6,
        bearAcc: 7.8,
        batt: 81,
        bs: 'unplugged',
        transport: 'driving',
      );
      final settings = settingsFor(
        ShareTemplate.dawarich,
        url: 'https://dawarich.test/api/v1/points',
      );
      expect(pointsPerRequest(settings), 100);
      final body = buildRequest(settings, [full]).body!;
      final feature = (body['locations']! as List).single as Map;
      expect(feature['properties'], {
        'timestamp': '2026-09-21T14:13:20Z',
        'horizontal_accuracy': 5,
        'altitude': 3,
        'vertical_accuracy': 3,
        'speed': 27.77,
        'course': 88.5,
        'course_accuracy': 8,
        'battery_level': 0.81,
        'battery_state': 'unplugged',
        'motion': ['driving'],
        'device_id': 'homemaps',
      });
    });

    test('Dawarich via OwnTracks from before becomes /api/v1/points', () {
      final old = ShareSettings.fromMap({
        'enabled': true,
        'template': 'dawarich',
        'url': 'https://d.test/api/v1/owntracks/points?api_key=abc',
        'extraFields': {'_type': 'location'},
      });
      expect(old.url, 'https://d.test/api/v1/points?api_key=abc');
      expect(old.extraFields, {'device_id': 'homemaps'});
      expect(old.enabled, isTrue);
    });

    test('PhoneTrack: speed, timestamp and bearing', () {
      final b = buildRequest(settingsFor(ShareTemplate.phonetrack), [
        point,
      ]).body!;
      expect(b['speed'], 27.8);
      expect(b['timestamp'], 1790000000);
      expect(b['bearing'], 88.5);
      expect(b['useragent'], 'HomeMaps');
      expect(b.containsKey('vel'), isFalse);
    });

    test('Traccar: OsmAnd query for GET, JSON for POST', () {
      final get = buildRequest(
        settingsFor(
          ShareTemplate.traccar,
          url: 'http://10.0.0.2:5055/?extra=1',
        ),
        [point],
      );
      expect(get.method, ShareMethod.get);
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

      final post = buildRequest(
        settingsFor(ShareTemplate.traccar).copyWith(method: ShareMethod.post),
        [point],
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

    test('Overland: all points in one GeoJSON envelope', () {
      final v = buildRequest(settingsFor(ShareTemplate.overland), [
        point,
        point,
      ]);
      final body = v.body!;
      expect(body['device_id'], 'homemaps');
      final locations = body['locations']! as List;
      expect(locations, hasLength(2));
      expect(locations.first, {
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
          'device_id': 'homemaps',
        },
      });
      expect(pointsPerRequest(settingsFor(ShareTemplate.overland)), 100);
      expect(pointsPerRequest(settingsFor(ShareTemplate.owntracks)), 1);
    });

    test('custom: own field names, and authentication', () {
      final props = settingsFor(ShareTemplate.custom).copyWith(
        fieldNames: {'lat': 'latitude', 'lon': 'longitude', 'vel': ''},
        extraFields: {'device': 'car'},
        auth: ShareAuth.basic,
        username: 'jan',
        secret: 'secret',
      );
      final v = buildRequest(props, [point]);
      expect(v.body!['latitude'], 52.09);
      expect(v.body!['vel'], 27.8);
      expect(v.body!['device'], 'car');
      expect(
        v.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('jan:secret'))}',
      );
      final token = buildRequest(
        props.copyWith(auth: ShareAuth.bearer, secret: 'abc'),
        [point],
      );
      expect(token.headers['Authorization'], 'Bearer abc');
    });

    test('settings across a restart, without the secret', () {
      final saved = ShareSettings.fromMap(
        settingsFor(ShareTemplate.traccar)
            .copyWith(secret: 'x', interval: 30)
            .toMap(),
      );
      expect(saved.template, ShareTemplate.traccar);
      expect(saved.method, ShareMethod.get);
      expect(saved.interval, 30);
      expect(saved.extraFields, {'id': 'homemaps'});
      expect(saved.secret, '');
    });
  });

  group('sending while navigating', () {
    late ProviderContainer c;
    late FakeSource source;
    late FakeSender sender;

    ProviderContainer make({ShareQueue? queue}) {
      final container = ProviderContainer(
        overrides: [
          locationSourceProvider.overrideWithBuild((_, _) => source),
          shareSenderProvider.overrideWithValue(sender),
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
          batterySourceProvider.overrideWithValue(FakeBattery()),
          if (queue != null) shareQueueProvider.overrideWithValue(queue),
        ],
      );
      addTearDown(container.dispose);
      container.read(locationSharerProvider);
      return container;
    }

    Future<void> driveAt(double lat, DateTime time) async {
      source.fixes.add(
        LocationFix(
          point: LatLng(lat, 5.0),
          time: time,
          accuracy: 5,
          speed: 20,
          heading: 0,
        ),
      );
      await pumpEventQueue();
    }

    setUp(() async {
      source = FakeSource(PermissionAnswer.yes);
      sender = FakeSender();
      c = make();
      await c
          .read(shareSettingsProvider.notifier)
          .modify(settingsFor(ShareTemplate.owntracks));
      final wait = c.read(locationProvider.notifier).turnOn();
      await pumpEventQueue();
      source.fixes.add(fix(52.0));
      await wait;
      await pumpEventQueue();
    });

    final t0 = DateTime(2026, 9, 23, 12);

    test('nothing without navigation, or when it is off', () async {
      await driveAt(52.001, t0);
      expect(sender.requests, isEmpty);

      await c
          .read(shareSettingsProvider.notifier)
          .modify(
            settingsFor(ShareTemplate.owntracks).copyWith(enabled: false),
          );
      c.read(enRouteProvider.notifier).apply(true);
      await driveAt(52.002, t0);
      expect(sender.requests, isEmpty);
    });

    test('after the interval or the distance, not on every fix', () async {
      c.read(enRouteProvider.notifier).apply(true);
      await driveAt(52.0, t0);
      // 2 s later, 11 m further: too early and too close.
      await driveAt(52.0001, t0.add(const Duration(seconds: 2)));
      // 4 s later, 33 m further: far enough.
      await driveAt(52.0003, t0.add(const Duration(seconds: 4)));
      // 14 s later, standing still: long enough.
      await driveAt(52.0003, t0.add(const Duration(seconds: 14)));
      expect(sender.requests, hasLength(3));
      expect(c.read(locationSharerProvider).queued, 0);
      expect(c.read(locationSharerProvider).lastSent, isNotNull);
    });

    test(
      'to Dawarich with elevation, battery and the transport mode',
      () async {
        await c
            .read(shareSettingsProvider.notifier)
            .modify(
              settingsFor(
                ShareTemplate.dawarich,
                url: 'https://dawarich.test/api/v1/points',
              ),
            );
        c
            .read(settingsProvider.notifier)
            .modify(c.read(settingsProvider).copyWith(profile: Profile.bike));
        c.read(enRouteProvider.notifier).apply(true);
        source.fixes.add(
          LocationFix(
            point: const LatLng(52.0, 5.0),
            time: t0,
            accuracy: 5,
            speed: 6,
            heading: 90,
            elevation: 1.2,
            altitudeAccuracy: 3,
            headingAccuracy: 10,
          ),
        );
        await pumpEventQueue();
        final body = sender.requests.single.body!;
        final properties =
            ((body['locations']! as List).single as Map)['properties'] as Map;
        expect(properties['altitude'], 1);
        expect(properties['vertical_accuracy'], 3);
        expect(properties['course_accuracy'], 10);
        expect(properties['battery_level'], 0.64);
        expect(properties['battery_state'], 'charging');
        expect(properties['motion'], ['cycling']);
      },
    );

    test('without network into the queue, then in order', () async {
      c.read(enRouteProvider.notifier).apply(true);
      sender.offline = true;
      await driveAt(52.0, t0);
      expect(c.read(locationSharerProvider).queued, 1);
      expect(c.read(locationSharerProvider).error, contains('no network'));
      await driveAt(52.001, t0.add(const Duration(seconds: 20)));
      // Don't keep retrying while waiting.
      expect(c.read(locationSharerProvider).queued, 2);

      // Network back; we skip the sharer's backoff.
      sender.offline = false;
      await c
          .read(shareSettingsProvider.notifier)
          .modify(settingsFor(ShareTemplate.owntracks).copyWith(interval: 11));
      await pumpEventQueue();
      expect(c.read(locationSharerProvider).queued, 0);
      expect([for (final v in sender.requests) v.body!['lat']], [52.0, 52.001]);
    });

    test('a 401 is the settings: stop, and keep the points', () async {
      c.read(enRouteProvider.notifier).apply(true);
      sender.status = 401;
      await driveAt(52.0, t0);
      await driveAt(52.001, t0.add(const Duration(seconds: 20)));
      final status = c.read(locationSharerProvider);
      expect(status.stopped, isTrue);
      expect(status.error, 'HTTP 401');
      expect(status.queued, 2);
      // Only the first attempt; then no more until the settings change.
      expect(sender.requests, hasLength(1));
    });

    test('the queue across a restart', () async {
      final dir = await Directory.systemTemp.createTemp('queue');
      addTearDown(() => dir.delete(recursive: true));
      Hive.init(dir.path);
      final box = await Hive.openBox<dynamic>('shareQueue');
      addTearDown(box.close);
      final queue = ShareQueue(box);
      await queue.add(point);
      await queue.add(const SharedPoint(lat: 1, lon: 2, tst: 3));
      final again = ShareQueue(box);
      expect(again.length, 2);
      expect(again.first(1).single.lat, 52.09);
      await again.removeFirst(1);
      expect(again.first(5).single.lat, 1);
    });

    test('no more than the maximum', () async {
      final queue = ShareQueue();
      for (var i = 0; i < ShareQueue.maximum + 3; i++) {
        await queue.add(SharedPoint(lat: i.toDouble(), lon: 0, tst: i));
      }
      expect(queue.length, ShareQueue.maximum);
      // The oldest are dropped.
      expect(queue.first(1).single.lat, 3);
    });
  });

  testWidgets(
    'screen: choosing a server fills the fixed fields and the preview',
    (tester) async {
      tester.view.physicalSize = const Size(500, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = MemorySecretStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secretStoreProvider.overrideWithValue(storage),
            shareSenderProvider.overrideWithValue(FakeSender()),
          ],
          child: MaterialApp(
            locale: const Locale('nl'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsScreen(category: 'location-sharing'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // OwnTracks by default.
      expect(find.text('_type=location\ntid=HM'), findsOneWidget);

      await tester.tap(find.text('Traccar'));
      await tester.pumpAndSettle();
      expect(find.text('id=homemaps'), findsOneWidget);
      expect(find.text('POST'), findsOneWidget);

      // Turning on without an address is not allowed.
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
      // The preview: an OsmAnd GET.
      expect(find.textContaining('GET http://10.0.0.2:5055?'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LocationSharingSettings)),
      );
      final saved = container.read(shareSettingsProvider);
      expect(saved.enabled, isTrue);
      expect(saved.template, ShareTemplate.traccar);
      expect(saved.url, 'http://10.0.0.2:5055');
    },
  );
}
