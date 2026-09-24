import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:homemaps/models/location_sharing.dart';
import 'package:homemaps/models/profile.dart';
import 'package:homemaps/providers/location_sharing.dart';
import 'package:homemaps/providers/saved_places.dart';
import 'package:homemaps/providers/settings.dart';
import 'package:homemaps/providers/storage_migration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('migration');
    addTearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });
    Hive.init(dir.path);
  });

  test('settings, places, sharing and secrets of v1.0.0 move over', () async {
    final old = await Hive.openBox<dynamic>('instellingen');
    await old.putAll({
      'server': 'https://kaart.example',
      'stijl': 'positron',
      'thema': 'nacht',
      'profiel': 'fiets',
      'liveVerkeer': false,
      'vermijdSnelwegen': true,
      'verkeerOpKaart': false,
      'locatieAan': true,
      'thuis': {
        'naam': 'Thuis',
        'omschrijving': 'Stroe',
        'lat': 52.1,
        'lon': 5.7,
      },
      'recent': [
        {
          'naam': 'Bakker',
          'omschrijving': 'Barneveld',
          'lat': 52.3,
          'lon': 5.6,
        },
      ],
      'dawarich': {
        'server': 'https://d.example',
        'email': 'a@b.nl',
        'familie': false,
        'toonFamilie': true,
      },
      'dawarichVorigeServer': 'https://d.example',
      'locatieDelen': {
        'aan': true,
        'sjabloon': 'aangepast',
        'inlog': 'geen',
        'minAfstand': 50,
        'url': 'https://x',
      },
    });
    await old.close();
    final queue = await Hive.openBox<dynamic>('deelWachtrij');
    await queue.addAll([
      {'lat': 52.0, 'lon': 5.0, 'tst': 1, 'vervoer': 'driving'},
      {'lat': 52.1, 'lon': 5.1, 'tst': 2},
    ]);
    await queue.close();
    FlutterSecureStorage.setMockInitialValues({
      'locatieDelenGeheim': 'geheim',
      'dawarichSleutel': 'sleutel',
    });

    await migrateStorage();

    expect(await Hive.boxExists('instellingen'), isFalse);
    expect(await Hive.boxExists('deelWachtrij'), isFalse);
    final box = await Hive.openBox<dynamic>('settings');
    expect(box.get('dawarich'), containsPair('family', false));
    expect(box.get('dawarichPreviousServer'), 'https://d.example');
    expect(box.get('locationSharing'), {
      'enabled': true,
      'template': 'custom',
      'auth': 'none',
      'minDistance': 50,
      'url': 'https://x',
    });
    final share = ShareSettings.fromMap(box.get('locationSharing'));
    expect(share.template, ShareTemplate.custom);
    expect(share.minDistance, 50);

    final c = ProviderContainer(
      overrides: [settingsBoxProvider.overrideWithValue(box)],
    );
    addTearDown(c.dispose);
    final settings = c.read(settingsProvider);
    expect(settings.style, 'positron');
    expect(settings.theme, MapTheme.night);
    expect(settings.profile, Profile.bike);
    expect(settings.liveTraffic, isFalse);
    expect(settings.avoidMotorways, isTrue);
    expect(settings.trafficOnMap, isFalse);
    expect(settings.locationEnabled, isTrue);
    final places = c.read(savedPlacesProvider);
    expect(places.home?.label, 'Thuis');
    expect(places.home?.description, 'Stroe');
    expect(places.recent.single.label, 'Bakker');

    final points = ShareQueue(await Hive.openBox<dynamic>('shareQueue'));
    expect(points.length, 2);
    expect(points.first(2).map((p) => p.tst), [1, 2]);
    expect(
      (await Hive.openBox<dynamic>('shareQueue')).getAt(0),
      containsPair('transport', 'driving'),
    );

    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'locationSharingSecret'), 'geheim');
    expect(await storage.read(key: 'dawarichApiKey'), 'sleutel');
    expect(await storage.read(key: 'locatieDelenGeheim'), isNull);
  });

  test('runs once: without the old boxes nothing changes', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final box = await Hive.openBox<dynamic>('settings');
    await box.put('theme', 'day');
    await migrateStorage();
    await migrateStorage();
    expect(box.toMap(), {'theme': 'day'});
  });

  test('new data wins over a leftover old box', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await (await Hive.openBox<dynamic>('settings')).put('theme', 'day');
    await (await Hive.openBox<dynamic>('instellingen')).put('thema', 'nacht');
    await migrateStorage();
    expect((await Hive.openBox<dynamic>('settings')).get('theme'), 'day');
    expect(await Hive.boxExists('instellingen'), isFalse);
  });

  test('unknown stored enum names fall back to the defaults', () async {
    final box = await Hive.openBox<dynamic>('settings');
    await box.putAll(migrateSettings({'profiel': 'step', 'thema': 'x'}));
    final c = ProviderContainer(
      overrides: [settingsBoxProvider.overrideWithValue(box)],
    );
    addTearDown(c.dispose);
    expect(c.read(settingsProvider).profile, Profile.car);
    expect(c.read(settingsProvider).theme, MapTheme.automatic);
    final share = ShareSettings.fromMap({'template': 'nope', 'auth': 'nope'});
    expect(share.template, ShareTemplate.owntracks);
    expect(share.auth, ShareAuth.none);
  });
}
