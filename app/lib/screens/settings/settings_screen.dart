import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../router/app_router.dart';
import 'category.dart';
import 'section.dart';

/// From this width side by side: the categories on the left, the chosen one on
/// the right. The same breakpoint as on the map.
const _wideBreakpoint = 800.0;

/// The settings. Narrow: a list of categories, and a category as its own page
/// (`/settings/<category>`). Wide (a computer): both side by side.
@RoutePage()
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, @PathParam('category') this.category});

  /// The [SettingsCategory.path]; null for the list.
  final String? category;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Wide: what's on the right, if you chose something else in the list.
  SettingsCategory? _chosen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fromAddress = SettingsCategory.from(widget.category);
    return LayoutBuilder(
      builder: (context, space) {
        if (space.maxWidth >= _wideBreakpoint) {
          final chosen = _chosen ?? fromAddress ?? SettingsCategory.map;
          return Scaffold(
            appBar: AppBar(title: Text(l.settings)),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 300,
                  child: _CategoryList(
                    wide: true,
                    chosen: chosen,
                    onChoose: (c) => setState(() => _chosen = c),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _Detail(chosen, key: ValueKey(chosen))),
              ],
            ),
          );
        }
        if (fromAddress != null) {
          return Scaffold(
            appBar: AppBar(title: Text(fromAddress.title(l))),
            body: fromAddress.content(),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(l.settings)),
          body: _CategoryList(
            wide: false,
            onChoose: (c) =>
                context.router.push(SettingsCategoryRoute(category: c.path)),
          ),
        );
      },
    );
  }
}

/// `/settings/<category>`: the same settings, with that category open. A page
/// of its own, because auto_route wants a separate name per route.
@RoutePage()
class SettingsCategoryScreen extends StatelessWidget {
  const SettingsCategoryScreen({
    super.key,
    @PathParam('category') required this.category,
  });

  final String category;

  @override
  Widget build(BuildContext context) => SettingsScreen(category: category);
}

/// Wide: the category's title above its content, indented the same.
class _Detail extends StatelessWidget {
  const _Detail(this.category, {super.key});

  final SettingsCategory category;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, space) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              settingsMargin(space.maxWidth) + 16,
              24,
              settingsMargin(space.maxWidth),
              0,
            ),
            child: Text(
              category.title(l),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Expanded(child: category.content()),
        ],
      ),
    );
  }
}

/// The categories per group, with how they stand. Narrow in cards like the
/// rest of the settings; wide as a sidebar with the chosen one highlighted.
class _CategoryList extends ConsumerWidget {
  const _CategoryList({
    required this.wide,
    required this.onChoose,
    this.chosen,
  });

  final bool wide;
  final SettingsCategory? chosen;
  final ValueChanged<SettingsCategory> onChoose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final groups = [
      for (final group in SettingsGroup.values)
        (
          group,
          [
            for (final c in SettingsCategory.visible)
              if (c.group == group) c,
          ],
        ),
    ];
    Widget tile(SettingsCategory c) => ListTile(
      leading: Icon(c.icon),
      title: Text(c.title(l)),
      subtitle: Text(
        c.summary(ref, l),
        maxLines: wide ? 1 : 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: wide ? null : const Icon(Icons.chevron_right),
      selected: c == chosen,
      selectedTileColor: wide ? theme.colorScheme.secondaryContainer : null,
      selectedColor: wide ? theme.colorScheme.onSecondaryContainer : null,
      shape: wide ? const StadiumBorder() : null,
      onTap: () => onChoose(c),
    );

    if (wide) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final (group, categories) in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                group.title(l),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            for (final c in categories) tile(c),
          ],
        ],
      );
    }
    return SettingsList(
      children: [
        for (final (group, categories) in groups)
          SettingsSection(
            title: group.title(l),
            children: [for (final c in categories) tile(c)],
          ),
      ],
    );
  }
}
