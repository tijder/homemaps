import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/settings.dart';
import 'section.dart';

/// What the map looks like; the same choices as in the layers menu on the map.
class MapSettings extends ConsumerWidget {
  const MapSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final apply = ref.read(settingsProvider.notifier).modify;
    final style = MapStyle.from(settings.style);
    return SettingsList(
      children: [
        SettingsSection(
          title: l.mapStyle,
          children: [
            SectionBlock(
              child: SegmentedButton<MapStyle>(
                showSelectedIcon: false,
                segments: [
                  for (final s in MapStyle.values)
                    ButtonSegment(value: s, label: Text(s.label(l))),
                ],
                selected: {style},
                onSelectionChanged: (choice) =>
                    apply(settings.copyWith(style: choice.first.id)),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: l.dayAndNight,
          help: l.themeOnlyMap,
          children: [
            SectionBlock(
              child: SegmentedButton<MapTheme>(
                showSelectedIcon: false,
                segments: [
                  for (final t in MapTheme.values)
                    ButtonSegment(value: t, label: Text(t.label(l))),
                ],
                selected: {settings.theme},
                onSelectionChanged: style == MapStyle.map
                    ? (choice) => apply(settings.copyWith(theme: choice.first))
                    : null,
              ),
            ),
          ],
        ),
        SettingsSection(
          title: l.layers,
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.traffic_outlined),
              title: Text(l.trafficOnMap),
              subtitle: Text(l.trafficOnMapHelp),
              value: settings.trafficOnMap,
              onChanged: (enabled) =>
                  apply(settings.copyWith(trafficOnMap: enabled)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.photo_camera_outlined),
              title: Text(l.speedCameras),
              subtitle: Text(l.speedCamerasHelp),
              value: settings.speedCameras,
              onChanged: (enabled) =>
                  apply(settings.copyWith(speedCameras: enabled)),
            ),
          ],
        ),
      ],
    );
  }
}
