import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/profile.dart';
import '../../providers/dawarich.dart';
import '../../providers/settings.dart';
import '../../providers/location_sharing.dart';
import '../../providers/saved_places.dart';
import '../../widgets/route_preferences.dart';
import 'dawarich.dart';
import 'map.dart';
import 'location_sharing.dart';
import 'about.dart';
import 'saved_places.dart';
import 'route.dart';
import 'server.dart';

enum SettingsGroup {
  map,
  sharing,
  app;

  String title(AppLocalizations l) => switch (this) {
    map => l.settingsGroupMap,
    sharing => l.settingsGroupSharing,
    app => l.settingsGroupApp,
  };
}

/// The parts of the settings, in list order.
enum SettingsCategory {
  map('map', Icons.map_outlined, SettingsGroup.map),
  route('route', Icons.alt_route, SettingsGroup.map),
  savedPlaces('saved-places', Icons.place_outlined, SettingsGroup.map),
  dawarich('dawarich', Icons.family_restroom, SettingsGroup.sharing),
  locationSharing(
    'location-sharing',
    Icons.share_location,
    SettingsGroup.sharing,
  ),
  server('server', Icons.dns_outlined, SettingsGroup.app),
  about('about', Icons.info_outline, SettingsGroup.app);

  const SettingsCategory(this.path, this.icon, this.group);

  /// The last part of the address: `/settings/<path>`.
  final String path;
  final IconData icon;
  final SettingsGroup group;

  static SettingsCategory? from(String? path) =>
      visible.where((c) => c.path == path).firstOrNull;

  /// On the web the server is the page's own origin; nothing to configure there.
  static List<SettingsCategory> get visible => [
    for (final c in values)
      if (c != server || !kIsWeb) c,
  ];

  String title(AppLocalizations l) => switch (this) {
    map => l.settingsMap,
    route => l.route,
    savedPlaces => l.savedPlaces,
    dawarich => l.dawarich,
    locationSharing => l.locationSharing,
    server => l.server,
    about => l.aboutHomeMaps,
  };

  Widget content() => switch (this) {
    map => const MapSettings(),
    route => const RoutingSettings(),
    savedPlaces => const SavedPlacesSettings(),
    dawarich => const DawarichSettings(),
    locationSharing => const LocationSharingSettings(),
    server => const ServerSettings(),
    about => const AboutSettings(),
  };

  /// How things stand, in one line below the title in the list.
  String summary(WidgetRef ref, AppLocalizations l) {
    switch (this) {
      case map:
        final i = ref.watch(settingsProvider);
        final style = MapStyle.from(i.style);
        return [
          style.label(l),
          if (style == MapStyle.map) i.theme.label(l),
          if (i.trafficOnMap) l.trafficOnMap,
        ].join(' · ');
      case route:
        final i = ref.watch(settingsProvider);
        final car = i.profile == Profile.car;
        return [
          i.profile.label(l),
          if (car && i.liveTraffic) l.liveTraffic,
          if (car && i.avoidMotorways) l.avoidMotorways,
          if (car && i.avoidTolls) l.avoidTolls,
          if (i.avoidFerries) l.avoidFerries,
        ].join(' · ');
      case savedPlaces:
        final p = ref.watch(savedPlacesProvider);
        return [
          if (p.home != null) l.home,
          if (p.work != null) l.work,
          l.savedPlaceCount(p.recent.length),
        ].join(' · ');
      case dawarich:
        final account = ref.watch(dawarichProvider);
        if (account == null) return l.dawarichNotSignedIn;
        final isSharing =
            ref.watch(familyProvider).value?.sharingEnabled ?? false;
        return [
          account.email,
          if (isSharing) l.dawarichFamilySharing,
        ].join(' · ');
      case locationSharing:
        final share = ref.watch(shareSettingsProvider);
        final status = ref.watch(locationSharerProvider);
        if (!share.enabled) return l.shareOff;
        return [
          share.template.label ?? l.shareCustom,
          if (status.error case final error?) l.shareError(error),
          if (status.queued > 0) l.shareQueued(status.queued),
        ].join(' · ');
      case server:
        final address = ref.watch(settingsProvider).server;
        return address.isEmpty
            ? l.notSet
            : (Uri.tryParse(address)?.host ?? address);
      case about:
        return l.aboutSummary;
    }
  }
}
