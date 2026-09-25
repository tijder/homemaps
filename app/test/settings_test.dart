import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/models/profile.dart';
import 'package:homemaps/providers/settings.dart';
import 'package:homemaps/screens/settings/settings_screen.dart';

void main() {
  Future<ProviderContainer> showScreen(
    WidgetTester tester, {
    required Size size,
    String? category,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: const Locale('nl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(category: category),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('narrow: the categories in groups, with their current state', (
    tester,
  ) async {
    await showScreen(tester, size: const Size(500, 1400));
    expect(find.text('Kaart en route'), findsOneWidget);
    expect(find.text('Delen'), findsOneWidget);
    expect(find.text('App'), findsOneWidget);
    expect(
      find.text('Kaart · Automatisch · Verkeer · Flitsers'),
      findsOneWidget,
    );
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Niet ingelogd'), findsOneWidget);
    // Narrow has no sidebar: no category open.
    expect(find.byType(VerticalDivider), findsNothing);
  });

  testWidgets('narrow: map as its own page; light sets the style', (
    tester,
  ) async {
    final c = await showScreen(
      tester,
      size: const Size(500, 1400),
      category: 'map',
    );
    expect(find.widgetWithText(AppBar, 'Kaart'), findsOneWidget);
    await tester.tap(find.text('Licht'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).style, MapStyle.light.id);
    // Day and night only apply to the Map style.
    final theme = tester.widget<SegmentedButton<MapTheme>>(
      find.byType(SegmentedButton<MapTheme>),
    );
    expect(theme.onSelectionChanged, isNull);

    await tester.tap(find.text('Verkeer'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).trafficOnMap, isFalse);

    await tester.tap(find.text('Flitsers'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).speedCameras, isFalse);
  });

  testWidgets('wide: two panes, and choosing changes the right one', (
    tester,
  ) async {
    final c = await showScreen(tester, size: const Size(1400, 1000));
    expect(find.byType(VerticalDivider), findsOneWidget);
    // Starts at Map.
    expect(find.text('Kaartstijl'), findsOneWidget);

    await tester.tap(find.text('Route'));
    await tester.pumpAndSettle();
    expect(find.text('Kaartstijl'), findsNothing);
    expect(find.text('Snelwegen vermijden'), findsOneWidget);

    // By bike no motorways or tolls; the ferry stays.
    await tester.tap(find.text('Fiets'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).profile, Profile.bike);
    expect(find.text('Snelwegen vermijden'), findsNothing);
    expect(find.text('Veerponten vermijden'), findsOneWidget);
  });

  testWidgets('wide: a category from the address is open right away', (
    tester,
  ) async {
    await showScreen(
      tester,
      size: const Size(1400, 1000),
      category: 'dawarich',
    );
    expect(find.text('Verbinden'), findsOneWidget);
    final chosen = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where((t) => t.selected);
    expect(chosen, hasLength(1));
  });
}
