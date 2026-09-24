import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
      ],
    );
  }
}
