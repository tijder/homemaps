import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:homemaps/models/place.dart';
import 'package:homemaps/providers/settings.dart';
import 'package:homemaps/providers/saved_places.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

Place position(String label, double lat) =>
    Place(label: label, description: 'somewhere', point: LatLng(lat, 5.0));

void main() {
  test(
    'recent: newest first, no duplicates, at most eight, not "My location"',
    () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final savedPlaces = c.read(savedPlacesProvider.notifier);
      for (var i = 0; i < 10; i++) {
        savedPlaces.remember(position('P$i', 52 + i * 0.01));
      }
      savedPlaces.remember(position('P3 again', 52.03));
      savedPlaces.remember(Place.here(const LatLng(52.5, 5)));
      final recent = c.read(savedPlacesProvider).recent;
      expect(recent, hasLength(maxRecent));
      expect(recent.first.label, 'P3 again');
      expect(recent.where((p) => p.label.startsWith('P3')), hasLength(1));
      expect(recent.any((p) => p.myLocation), isFalse);
    },
  );

  test('home, work and recent are kept across a restart', () async {
    final dir = await Directory.systemTemp.createTemp('saved_places');
    addTearDown(() => dir.delete(recursive: true));
    Hive.init(dir.path);
    final box = await Hive.openBox<dynamic>('settings');
    addTearDown(box.close);

    ProviderContainer fresh() {
      final c = ProviderContainer(
        overrides: [settingsBoxProvider.overrideWithValue(box)],
      );
      addTearDown(c.dispose);
      return c;
    }

    final first = fresh();
    first.read(savedPlacesProvider.notifier)
      ..setHome(position('Home address', 52.1))
      ..setWork(position('Work address', 52.2))
      ..remember(position('Bakery', 52.3));

    final afterwards = fresh().read(savedPlacesProvider);
    expect(afterwards.home?.label, 'Home address');
    expect(afterwards.work?.point, const LatLng(52.2, 5.0));
    expect(afterwards.recent.single.description, 'somewhere');

    fresh().read(savedPlacesProvider.notifier)
      ..setHome(null)
      ..clearRecent();
    final cleared = fresh().read(savedPlacesProvider);
    expect(cleared.home, isNull);
    expect(cleared.work?.label, 'Work address');
    expect(cleared.recent, isEmpty);
  });
}
