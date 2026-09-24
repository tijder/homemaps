import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/saved_places.dart';
import 'section.dart';

/// View and remove home and work, and clear the recent places. Setting them
/// happens on the card of a found place.
class SavedPlacesSettings extends ConsumerWidget {
  const SavedPlacesSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final savedPlaces = ref.watch(savedPlacesProvider);
    final actions = ref.read(savedPlacesProvider.notifier);
    return SettingsList(
      children: [
        SettingsSection(
          title: l.savedPlaces,
          help: l.savedPlacesHelp,
          children: [
            for (final (icon, label, place, clear) in [
              (
                Icons.home_outlined,
                l.home,
                savedPlaces.home,
                () => actions.setHome(null),
              ),
              (
                Icons.work_outline,
                l.work,
                savedPlaces.work,
                () => actions.setWork(null),
              ),
            ])
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                subtitle: Text(place?.label ?? l.notSet),
                trailing: place == null
                    ? null
                    : IconButton(
                        tooltip: l.removeLabel,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: clear,
                      ),
              ),
          ],
        ),
        SettingsSection(
          children: [
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(l.recentPlaces),
              subtitle: Text(l.savedPlaceCount(savedPlaces.recent.length)),
              trailing: savedPlaces.recent.isEmpty
                  ? null
                  : TextButton(
                      onPressed: actions.clearRecent,
                      child: Text(l.clearLabel),
                    ),
            ),
          ],
        ),
      ],
    );
  }
}
