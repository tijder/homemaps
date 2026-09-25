import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/dawarich.dart';
import '../providers/location_sharing.dart';
import '../providers/settings.dart';
import '../router/app_router.dart';
import 'settings/dawarich.dart';
import 'settings/location_sharing.dart';
import 'settings/section.dart';
import 'settings/server.dart';

enum _Step { welcome, server, dawarich, locationSharing }

/// The first start: a word of welcome, the server (not on the web, where the
/// page's own origin is the server), and Dawarich and location sharing, which
/// can be skipped. The steps are the settings themselves, so everything can
/// be changed there later.
@RoutePage()
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  /// A web address that is about the map itself: a shared route (`?to=`) or
  /// a simulated drive (`?simulate=`, the browser tests). Those go straight
  /// to the map; the welcome comes on a later plain visit.
  static bool skippedFor(Uri address) =>
      address.queryParameters.containsKey('to') ||
      address.queryParameters.containsKey('simulate');

  /// Off to the map; replaceable in tests, where the map can't be built.
  @visibleForTesting
  static void Function(BuildContext context) leave = (context) =>
      context.router.replaceAll([const MapRoute()]);

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<OnboardingScreen> {
  static final _steps = [
    for (final step in _Step.values)
      if (step != _Step.server || !kIsWeb) step,
  ];

  int _index = 0;

  _Step get _step => _steps[_index];
  bool get _last => _index == _steps.length - 1;

  void _next() {
    if (!_last) {
      setState(() => _index++);
      return;
    }
    ref
        .read(settingsProvider.notifier)
        .modify(ref.read(settingsProvider).copyWith(setupDone: true));
    OnboardingScreen.leave(context);
  }

  void _back() => setState(() => _index--);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final step = _step;
    final (title, intro) = switch (step) {
      _Step.welcome => (null, null),
      _Step.server => (l.server, l.setupServerIntro),
      _Step.dawarich => (l.dawarich, l.setupDawarichIntro),
      _Step.locationSharing => (l.locationSharing, l.setupSharingIntro),
    };
    // An optional step says "Skip" as long as nothing has been set up there.
    final configured = switch (step) {
      _Step.welcome => true,
      _Step.server => ref.watch(settingsProvider).server.isNotEmpty,
      _Step.dawarich => ref.watch(dawarichProvider) != null,
      _Step.locationSharing => ref.watch(shareSettingsProvider).enabled,
    };
    final (String label, bool enabled) = switch (step) {
      _Step.welcome => (l.getStarted, true),
      _Step.server => (l.next, configured),
      _ when !configured => (_last ? l.skipAndStart : l.skip, true),
      _ => (_last ? l.toTheMap : l.next, true),
    };
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, space) {
              final margin = settingsMargin(space.maxWidth);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        margin + 16,
                        16,
                        margin + 16,
                        0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LinearProgressIndicator(
                            value: _index / (_steps.length - 1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l.setupStep(_index, _steps.length - 1),
                            style: theme.textTheme.labelMedium,
                          ),
                          const SizedBox(height: 16),
                          Text(title, style: theme.textTheme.headlineSmall),
                          const SizedBox(height: 8),
                          Text(intro!),
                        ],
                      ),
                    ),
                  Expanded(
                    child: KeyedSubtree(
                      key: ValueKey(step),
                      child: switch (step) {
                        _Step.welcome => const _Welcome(),
                        _Step.server => const ServerSettings(
                          saveWhenWorking: true,
                        ),
                        _Step.dawarich => const DawarichSettings(),
                        _Step.locationSharing =>
                          const LocationSharingSettings(),
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(margin, 8, margin, 16),
                    child: Row(
                      children: [
                        if (_index > 0)
                          TextButton(onPressed: _back, child: Text(l.back)),
                        const Spacer(),
                        FilledButton(
                          onPressed: enabled ? _next : null,
                          child: Text(label),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return SettingsList(
      children: [
        const SizedBox(height: 48),
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset('assets/icon/icon.png', width: 112, height: 112),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          l.welcomeTitle,
          style: text.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          l.aboutDescription,
          style: text.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Text(
          kIsWeb ? l.welcomeTextWeb : l.welcomeText,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
