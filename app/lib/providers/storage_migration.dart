import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

// Up to v1.0.0 the storage had Dutch names. On the first start after that
// everything moves once to the English names and the old box goes away; after
// that there is nothing left to do.

const _settingsKeys = {
  'stijl': 'style',
  'thema': 'theme',
  'profiel': 'profile',
  'liveVerkeer': 'liveTraffic',
  'vermijdSnelwegen': 'avoidHighways',
  'vermijdTol': 'avoidTolls',
  'vermijdVeren': 'avoidFerries',
  'verkeerOpKaart': 'trafficOnMap',
  'locatieAan': 'locationOn',
  'thuis': 'home',
  'werk': 'work',
  'dawarichVorigeServer': 'dawarichPreviousServer',
  'locatieDelen': 'locationSharing',
};

const _placeKeys = {'naam': 'name', 'omschrijving': 'description'};

const _dawarichKeys = {'familie': 'family', 'toonFamilie': 'showFamily'};

const _shareKeys = {
  'aan': 'enabled',
  'sjabloon': 'template',
  'methode': 'method',
  'veldnamen': 'fieldNames',
  'extraVelden': 'extraFields',
  'inlog': 'auth',
  'gebruiker': 'username',
  'minAfstand': 'minDistance',
};

const _queueKeys = {'vervoer': 'transport'};

/// Enums stored by `.name`, under their new key. The other names (style ids,
/// `post`/`get`, `basic`/`bearer`, the other templates) did not change.
const _enumValues = {
  'theme': {'automatisch': 'automatic', 'dag': 'day', 'nacht': 'night'},
  'profile': {'auto': 'car', 'fiets': 'bike', 'lopen': 'walk'},
  'template': {'aangepast': 'custom'},
  'auth': {'geen': 'none'},
};

const _secretKeys = {
  'locatieDelenGeheim': 'locationSharingSecret',
  'dawarichSleutel': 'dawarichApiKey',
};

Map<String, dynamic> _rename(
  Map<dynamic, dynamic> old,
  Map<String, String> keys,
) {
  final renamed = <String, dynamic>{};
  old.forEach((key, value) {
    final name = keys[key] ?? '$key';
    renamed[name] = _enumValues[name]?[value] ?? value;
  });
  return renamed;
}

Object? _nested(Object? value, Map<String, String> keys) =>
    value is Map ? _rename(value, keys) : value;

/// The settings box of v1.0.0 under the new names.
@visibleForTesting
Map<String, dynamic> migrateSettings(Map<dynamic, dynamic> old) => {
  for (final MapEntry(:key, :value) in _rename(old, _settingsKeys).entries)
    key: switch (key) {
      'home' || 'work' => _nested(value, _placeKeys),
      'recent' =>
        value is List
            ? [for (final place in value) _nested(place, _placeKeys)]
            : value,
      'dawarich' => _nested(value, _dawarichKeys),
      'locationSharing' => _nested(value, _shareKeys),
      _ => value,
    },
};

/// A point in the sharing queue of v1.0.0 under the new names.
@visibleForTesting
Object? migrateQueuedPoint(Object? old) => _nested(old, _queueKeys);

/// Call after `Hive.init` and before the boxes are opened.
Future<void> migrateStorage({
  FlutterSecureStorage secure = const FlutterSecureStorage(),
}) async {
  if (await Hive.boxExists('instellingen')) {
    for (final MapEntry(key: old, value: name) in _secretKeys.entries) {
      try {
        final secret = await secure.read(key: old);
        if (secret == null) continue;
        if (await secure.read(key: name) == null) {
          await secure.write(key: name, value: secret);
        }
        await secure.delete(key: old);
      } on Object catch (error) {
        debugPrint('Could not migrate secret $old: $error');
      }
    }
  }
  await _migrateBox(
    'instellingen',
    'settings',
    (old, box) => box.putAll(migrateSettings(old.toMap())),
  );
  await _migrateBox(
    'deelWachtrij',
    'shareQueue',
    (old, box) => box.addAll(old.values.map(migrateQueuedPoint)),
  );
}

/// Copies [oldName] into [newName] if that is still empty, then deletes it.
Future<void> _migrateBox(
  String oldName,
  String newName,
  Future<void> Function(Box<dynamic> old, Box<dynamic> box) copy,
) async {
  if (!await Hive.boxExists(oldName)) return;
  final old = await Hive.openBox<dynamic>(oldName);
  final target = await Hive.openBox<dynamic>(newName);
  if (target.isEmpty) await copy(old, target);
  await old.deleteFromDisk();
}
