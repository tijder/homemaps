import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/place.dart';
import '../utils/distance.dart';
import 'settings.dart';

/// Home, work and the most recently chosen destinations.
@immutable
class SavedPlaces {
  const SavedPlaces({this.home, this.work, this.recent = const []});

  final Place? home;
  final Place? work;

  /// Newest first.
  final List<Place> recent;
}

/// How many recent places are kept.
const maxRecent = 8;

class SavedPlacesNotifier extends Notifier<SavedPlaces> {
  @override
  SavedPlaces build() {
    final box = ref.watch(settingsBoxProvider);
    if (box == null) return const SavedPlaces();
    return SavedPlaces(
      home: _read(box.get('home')),
      work: _read(box.get('work')),
      recent: [
        for (final value in (box.get('recent') as List? ?? const []))
          ?_read(value),
      ],
    );
  }

  void setHome(Place? place) {
    state = SavedPlaces(home: place, work: state.work, recent: state.recent);
    _save();
  }

  void setWork(Place? place) {
    state = SavedPlaces(home: state.home, work: place, recent: state.recent);
    _save();
  }

  void clearRecent() {
    state = SavedPlaces(home: state.home, work: state.work);
    _save();
  }

  /// A place the user chose: first among the recent ones, without duplicates
  /// (the same place within 30 m counts as the same). Not "My location": that
  /// is somewhere else every time.
  void remember(Place place) {
    if (place.myLocation) return;
    state = SavedPlaces(
      home: state.home,
      work: state.work,
      recent: [
        place,
        for (final old in state.recent)
          if (meters(old.point, place.point) > 30) old,
      ].take(maxRecent).toList(),
    );
    _save();
  }

  void _save() {
    ref.read(settingsBoxProvider)?.putAll({
      'home': _write(state.home),
      'work': _write(state.work),
      'recent': [for (final place in state.recent) _write(place)],
    });
  }

  static Map<String, dynamic>? _write(Place? place) => place == null
      ? null
      : {
          'name': place.label,
          'description': place.description,
          'lat': place.point.latitude,
          'lon': place.point.longitude,
        };

  static Place? _read(Object? value) {
    if (value is! Map) return null;
    final lat = value['lat'], lon = value['lon'];
    if (lat is! num || lon is! num) return null;
    return Place(
      label: value['name'] as String? ?? '',
      description: value['description'] as String? ?? '',
      point: LatLng(lat.toDouble(), lon.toDouble()),
    );
  }
}

final savedPlacesProvider = NotifierProvider<SavedPlacesNotifier, SavedPlaces>(
  SavedPlacesNotifier.new,
);
