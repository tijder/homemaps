import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/navigatie/navigatie_provider.dart';
import 'package:homemaps/widgets/navigatie_balk.dart';

import 'navigatie_test.dart' show stroe;

void main() {
  testWidgets('voorstel op telefoonbreedte: tekst, via en beide knoppen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(380, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var genomen = false, genegeerd = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: VoorstelKaart(
              Voorstel(
                stroe(),
                250,
                DateTime.now().add(const Duration(seconds: 45)),
              ),
              onNemen: () => genomen = true,
              onNegeren: () => genegeerd = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Snellere route: 4 min sneller'), findsOneWidget);
    // De langste manoeuvre met een naam in de Stroe-route.
    expect(find.textContaining('via '), findsOneWidget);
    await tester.tap(find.text('Nemen'));
    await tester.tap(find.text('Negeren'));
    expect((genomen, genegeerd), (true, true));
    expect(tester.takeException(), isNull);
  });
}
