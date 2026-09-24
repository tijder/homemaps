import 'dart:math';

import 'package:flutter/material.dart';

/// A category is at most this wide; that keeps it readable on a
/// computer.
const settingsMaxWidth = 720.0;

/// The margin left and right: 16, or more when the screen is wider than
/// [settingsMaxWidth], so the content is centred.
double settingsMargin(double width) => max(16, (width - settingsMaxWidth) / 2);

/// A category: a list that is centred on a wide screen, with the scrollbar
/// still at the edge.
class SettingsList extends StatelessWidget {
  const SettingsList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, space) => ListView(
      padding: EdgeInsets.symmetric(
        horizontal: settingsMargin(space.maxWidth),
        vertical: 16,
      ),
      children: children,
    ),
  );
}

/// A group of settings: a heading, optionally an explanation, and a card with
/// the rows in it.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    this.title,
    this.help,
    required this.children,
  });

  final String? title;
  final String? help;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                title!,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          if (help != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(help!, style: theme.textTheme.bodySmall),
            ),
          Card.filled(
            margin: EdgeInsets.zero,
            color: theme.colorScheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// A block with space around it in a [SettingsSection], for fields and
/// buttons that aren't a `ListTile`.
class SectionBlock extends StatelessWidget {
  const SectionBlock({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(16), child: child);
}
