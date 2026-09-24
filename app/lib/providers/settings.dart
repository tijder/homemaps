import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../l10n/app_localizations.dart';
import '../models/profile.dart';
import 'storage_migration.dart';

/// The tileserver's map styles, with their id in the style URL.
enum MapStyle {
  map('osm-bright'),
  light('positron'),
  dark('dark-matter');

  const MapStyle(this.id);

  final String id;

  String label(AppLocalizations l) => switch (this) {
    map => l.styleMap,
    light => l.styleLight,
    dark => l.styleDark,
  };

  static MapStyle from(String id) =>
      values.firstWhere((s) => s.id == id, orElse: () => map);
}

/// Day or night version of the map: following the phone, or always one of
/// the two.
enum MapTheme {
  automatic,
  day,
  night;

  String label(AppLocalizations l) => switch (this) {
    automatic => l.themeAutomatic,
    day => l.themeDay,
    night => l.themeNight,
  };
}

/// What the user sets and what has to survive a restart.
class Settings {
  const Settings({
    this.server = '',
    this.style = 'osm-bright',
    this.theme = MapTheme.automatic,
    this.profile = Profile.car,
    this.liveTraffic = true,
    this.avoidMotorways = false,
    this.avoidTolls = false,
    this.avoidFerries = false,
    this.trafficOnMap = true,
    this.locationEnabled = false,
  });

  /// Only needed on Android: on the web the server is the app's own origin.
  final String server;
  final String style;

  /// Only for the "Map" style; "Light" and "Dark" already are a choice.
  final MapTheme theme;
  final Profile profile;
  final bool liveTraffic;
  final bool avoidMotorways;
  final bool avoidTolls;
  final bool avoidFerries;

  /// Closures, roadworks and jams as a layer over the map.
  final bool trafficOnMap;

  /// The user turned their location on: again on the next start, if the
  /// permission is still there.
  final bool locationEnabled;

  Settings copyWith({
    String? server,
    String? style,
    MapTheme? theme,
    Profile? profile,
    bool? liveTraffic,
    bool? avoidMotorways,
    bool? avoidTolls,
    bool? avoidFerries,
    bool? trafficOnMap,
    bool? locationEnabled,
  }) => Settings(
    server: server ?? this.server,
    style: style ?? this.style,
    theme: theme ?? this.theme,
    profile: profile ?? this.profile,
    liveTraffic: liveTraffic ?? this.liveTraffic,
    avoidMotorways: avoidMotorways ?? this.avoidMotorways,
    avoidTolls: avoidTolls ?? this.avoidTolls,
    avoidFerries: avoidFerries ?? this.avoidFerries,
    trafficOnMap: trafficOnMap ?? this.trafficOnMap,
    locationEnabled: locationEnabled ?? this.locationEnabled,
  );
}

const _box = 'settings';

/// Opens the storage; call before runApp.
Future<Box<dynamic>> openSettings() async {
  await Hive.initFlutter();
  await migrateStorage();
  return Hive.openBox<dynamic>(_box);
}

/// Overridden in main() with the opened box; in tests with an empty one.
final settingsBoxProvider = Provider<Box<dynamic>?>((ref) => null);

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() {
    final box = ref.watch(settingsBoxProvider);
    if (box == null) return const Settings();
    return Settings(
      server: box.get('server', defaultValue: '') as String,
      style: box.get('style', defaultValue: 'osm-bright') as String,
      theme: MapTheme.values.firstWhere(
        (t) => t.name == box.get('theme'),
        orElse: () => MapTheme.automatic,
      ),
      profile: Profile.values.firstWhere(
        (p) => p.name == box.get('profile'),
        orElse: () => Profile.car,
      ),
      liveTraffic: box.get('liveTraffic', defaultValue: true) as bool,
      avoidMotorways: box.get('avoidHighways', defaultValue: false) as bool,
      avoidTolls: box.get('avoidTolls', defaultValue: false) as bool,
      avoidFerries: box.get('avoidFerries', defaultValue: false) as bool,
      trafficOnMap: box.get('trafficOnMap', defaultValue: true) as bool,
      locationEnabled: box.get('locationOn', defaultValue: false) as bool,
    );
  }

  void modify(Settings newValue) {
    state = newValue;
    ref.read(settingsBoxProvider)?.putAll({
      'server': newValue.server,
      'style': newValue.style,
      'theme': newValue.theme.name,
      'profile': newValue.profile.name,
      'liveTraffic': newValue.liveTraffic,
      'avoidHighways': newValue.avoidMotorways,
      'avoidTolls': newValue.avoidTolls,
      'avoidFerries': newValue.avoidFerries,
      'trafficOnMap': newValue.trafficOnMap,
      'locationOn': newValue.locationEnabled,
    });
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(
  SettingsNotifier.new,
);
