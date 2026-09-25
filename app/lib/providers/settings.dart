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
    this.speedCameras = true,
    this.locationEnabled = false,
    this.setupDone = true,
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

  /// Speed cameras, average speed sections and red light cameras: on the map
  /// and in the sign en route.
  final bool speedCameras;

  /// The user turned their location on: again on the next start, if the
  /// permission is still there.
  final bool locationEnabled;

  /// The first start is behind us: server set, the optional parts seen.
  final bool setupDone;

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
    bool? speedCameras,
    bool? locationEnabled,
    bool? setupDone,
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
    speedCameras: speedCameras ?? this.speedCameras,
    locationEnabled: locationEnabled ?? this.locationEnabled,
    setupDone: setupDone ?? this.setupDone,
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
      speedCameras: box.get('speedCameras', defaultValue: true) as bool,
      locationEnabled: box.get('locationOn', defaultValue: false) as bool,
      // Anything saved before means an installation from before the first
      // start existed; that one doesn't have to start over.
      setupDone: box.get('setupDone') as bool? ?? box.containsKey('style'),
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
      'speedCameras': newValue.speedCameras,
      'locationOn': newValue.locationEnabled,
      'setupDone': newValue.setupDone,
    });
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(
  SettingsNotifier.new,
);
