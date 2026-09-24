import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/profile.dart';
import '../providers/settings.dart';

extension ProfileLabel on Profile {
  String label(AppLocalizations l) => switch (this) {
    Profile.car => l.profileCar,
    Profile.bike => l.profileBike,
    Profile.walk => l.profileWalk,
  };

  IconData get icon => switch (this) {
    Profile.car => Icons.directions_car,
    Profile.bike => Icons.directions_bike,
    Profile.walk => Icons.directions_walk,
  };
}

/// Car, bike or walk; in the route panel and in the settings.
class ProfileChoice extends ConsumerWidget {
  const ProfileChoice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final apply = ref.read(settingsProvider.notifier).modify;
    return SegmentedButton<Profile>(
      showSelectedIcon: false,
      segments: [
        for (final profile in Profile.values)
          ButtonSegment(
            value: profile,
            icon: Icon(profile.icon),
            label: Text(profile.label(l)),
          ),
      ],
      selected: {settings.profile},
      onSelectionChanged: (choice) =>
          apply(settings.copyWith(profile: choice.first)),
    );
  }
}

/// Live traffic and what the route avoids. Motorways, tolls and live traffic
/// only apply to the car.
class RoutePreferences extends ConsumerWidget {
  const RoutePreferences({super.key, this.dense = false});

  /// Small, as in the route panel.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final apply = ref.read(settingsProvider.notifier).modify;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (settings.profile == Profile.car) ...[
          SwitchListTile(
            dense: dense,
            title: Text(l.liveTraffic),
            subtitle: Text(l.liveTrafficHelp),
            value: settings.liveTraffic,
            onChanged: (enabled) =>
                apply(settings.copyWith(liveTraffic: enabled)),
          ),
          SwitchListTile(
            dense: dense,
            title: Text(l.avoidMotorways),
            value: settings.avoidMotorways,
            onChanged: (enabled) =>
                apply(settings.copyWith(avoidMotorways: enabled)),
          ),
          SwitchListTile(
            dense: dense,
            title: Text(l.avoidTolls),
            value: settings.avoidTolls,
            onChanged: (enabled) =>
                apply(settings.copyWith(avoidTolls: enabled)),
          ),
        ],
        SwitchListTile(
          dense: dense,
          title: Text(l.avoidFerries),
          value: settings.avoidFerries,
          onChanged: (enabled) =>
              apply(settings.copyWith(avoidFerries: enabled)),
        ),
      ],
    );
  }
}
