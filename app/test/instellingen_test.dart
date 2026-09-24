import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/models/profiel.dart';
import 'package:homemaps/providers/instellingen.dart';
import 'package:homemaps/screens/instellingen/instellingen_screen.dart';

void main() {
  Future<ProviderContainer> toon(
    WidgetTester tester, {
    required Size maat,
    String? categorie,
  }) async {
    tester.view.physicalSize = maat;
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
          home: InstellingenScreen(categorie: categorie),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('smal: de categorieën in groepen, met hoe ze ervoor staan', (
    tester,
  ) async {
    await toon(tester, maat: const Size(500, 1400));
    expect(find.text('Kaart en route'), findsOneWidget);
    expect(find.text('Delen'), findsOneWidget);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('Kaart · Automatisch · Verkeer'), findsOneWidget);
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Niet ingelogd'), findsOneWidget);
    // Smal geen zijbalk: geen categorie open.
    expect(find.byType(VerticalDivider), findsNothing);
  });

  testWidgets('smal: kaart als eigen pagina; licht zet de stijl', (
    tester,
  ) async {
    final c = await toon(
      tester,
      maat: const Size(500, 1400),
      categorie: 'kaart',
    );
    expect(find.widgetWithText(AppBar, 'Kaart'), findsOneWidget);
    await tester.tap(find.text('Licht'));
    await tester.pumpAndSettle();
    expect(c.read(instellingenProvider).stijl, KaartStijl.licht.id);
    // Dag en nacht geldt alleen voor de stijl Kaart.
    final thema = tester.widget<SegmentedButton<KaartThema>>(
      find.byType(SegmentedButton<KaartThema>),
    );
    expect(thema.onSelectionChanged, isNull);

    await tester.tap(find.text('Verkeer'));
    await tester.pumpAndSettle();
    expect(c.read(instellingenProvider).verkeerOpKaart, isFalse);
  });

  testWidgets('breed: twee panelen, en kiezen verandert rechts', (
    tester,
  ) async {
    final c = await toon(tester, maat: const Size(1400, 1000));
    expect(find.byType(VerticalDivider), findsOneWidget);
    // Begint bij Kaart.
    expect(find.text('Kaartstijl'), findsOneWidget);

    await tester.tap(find.text('Route'));
    await tester.pumpAndSettle();
    expect(find.text('Kaartstijl'), findsNothing);
    expect(find.text('Snelwegen vermijden'), findsOneWidget);

    // Op de fiets geen snelwegen of tol; de veerpont blijft.
    await tester.tap(find.text('Fiets'));
    await tester.pumpAndSettle();
    expect(c.read(instellingenProvider).profiel, Profiel.fiets);
    expect(find.text('Snelwegen vermijden'), findsNothing);
    expect(find.text('Veerponten vermijden'), findsOneWidget);
  });

  testWidgets('breed: een categorie uit het adres staat meteen open', (
    tester,
  ) async {
    await toon(tester, maat: const Size(1400, 1000), categorie: 'dawarich');
    expect(find.text('Verbinden'), findsOneWidget);
    final gekozen = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where((t) => t.selected);
    expect(gekozen, hasLength(1));
  });
}
