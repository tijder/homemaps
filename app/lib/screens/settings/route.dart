import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/units.dart';
import '../../providers/settings.dart';
import '../../widgets/route_preferences.dart';
import 'section.dart';

/// The mode of transport and the route options; the same as in the route panel.
class RoutingSettings extends StatelessWidget {
  const RoutingSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SettingsList(
      children: [
        SettingsSection(
          title: l.transport,
          help: l.transportHelp,
          children: const [SectionBlock(child: ProfileChoice())],
        ),
        SettingsSection(title: l.options, children: const [RoutePreferences()]),
        SettingsSection(
          title: l.units,
          help: l.unitsHelp,
          children: const [SectionBlock(child: _UnitsChoice())],
        ),
      ],
    );
  }
}

class _UnitsChoice extends ConsumerWidget {
  const _UnitsChoice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    return SegmentedButton<Units>(
      segments: [
        for (final units in Units.values)
          ButtonSegment(value: units, label: Text(units.label(l))),
      ],
      selected: {settings.units},
      onSelectionChanged: (chosen) => ref
          .read(settingsProvider.notifier)
          .modify(settings.copyWith(units: chosen.single)),
    );
  }
}
