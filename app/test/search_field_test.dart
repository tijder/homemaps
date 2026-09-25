import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/widgets/search_field.dart';

void main() {
  testWidgets('closing the keyboard closes the suggestions too', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('nl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SearchField(
              label: 'Zoek hier',
              place: null,
              onChosen: (_) {},
              onCleared: () {},
              myLocation: () async => null,
            ),
          ),
        ),
      ),
    );
    addTearDown(tester.view.reset);

    await tester.tap(find.byType(TextField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(find.text('Mijn locatie'), findsOneWidget);

    // Back on Android: the system closes the keyboard, Flutter sees only that.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Mijn locatie'), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>(),
      isNull,
    );
  });

  testWidgets('without a keyboard (a computer) the field keeps its focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('nl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SearchField(
              label: 'Zoek hier',
              place: null,
              onChosen: (_) {},
              onCleared: () {},
              myLocation: () async => null,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Mijn locatie'), findsOneWidget);
  });
}
