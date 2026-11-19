import 'package:material_ui/material_ui.dart';
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
            for (final (icon, label, place, set) in [
              (Icons.home_outlined, l.home, savedPlaces.home, actions.setHome),
              (Icons.work_outline, l.work, savedPlaces.work, actions.setWork),
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
                        onPressed: () {
                          set(null);
                          _removed(
                            context,
                            l.placeRemoved(label),
                            () => set(place),
                          );
                        },
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
                      onPressed: () {
                        final recent = savedPlaces.recent;
                        actions.clearRecent();
                        _removed(
                          context,
                          l.recentCleared,
                          () => actions.setRecent(recent),
                        );
                      },
                      child: Text(l.clearLabel),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  /// Says what went, with a way back: one tap removes, and a home address is
  /// more work to set again than to remove.
  static void _removed(BuildContext context, String text, VoidCallback undo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: SnackBarAction(
            label: AppLocalizations.of(context).undo,
            onPressed: undo,
          ),
        ),
      );
  }
}
