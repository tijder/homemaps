import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/navigation/navigation_provider.dart';
import 'package:homemaps/widgets/navigation_bar.dart';

import 'navigation_test.dart' show stroe;

void main() {
  testWidgets('suggestion at phone width: text, via and both buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var accepted = false, ignored = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SuggestionCard(
              Suggestion(
                stroe(),
                250,
                DateTime.now().add(const Duration(seconds: 45)),
              ),
              onAccept: () => accepted = true,
              onIgnore: () => ignored = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Snellere route: 4 min sneller'), findsOneWidget);
    // The longest named maneuver in the Stroe route.
    expect(find.textContaining('via '), findsOneWidget);
    await tester.tap(find.text('Nemen'));
    await tester.tap(find.text('Negeren'));
    expect((accepted, ignored), (true, true));
    expect(tester.takeException(), isNull);
  });
}
