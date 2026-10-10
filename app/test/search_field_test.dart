import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/models/place.dart';
import 'package:homemaps/providers/saved_places.dart';
import 'package:homemaps/providers/services.dart';
import 'package:homemaps/services/photon_service.dart';
import 'package:homemaps/widgets/search_field.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class _FakePhoton extends PhotonService {
  _FakePhoton() : super(Dio(), 'http://photon.test');

  @override
  Future<List<Place>> search(
    String text, {
    LatLng? near,
    CancelToken? cancel,
  }) async => [
    for (var i = 0; i < 3; i++)
      Place(label: '$text $i', point: LatLng(52.0 + i, 5.0)),
  ];
}

void main() {
  testWidgets('a click that first takes the focus (browsers) still picks the '
      'search result and not the recent place under it', (tester) async {
    Place? chosen;
    // A fresh tree each time, so the second pump really rebuilds everything.
    Widget app() => ProviderScope(
      overrides: [photonProvider.overrideWithValue(_FakePhoton())],
      child: MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SearchField(
            label: 'Zoek hier',
            place: null,
            onChosen: (place) => chosen = place,
            onCleared: () {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(app());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchField)),
    );
    for (var i = 0; i < 5; i++) {
      container
          .read(savedPlacesProvider.notifier)
          .remember(Place(label: 'Recent $i', point: LatLng(51.0 + i, 4.0)));
    }

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.textContaining('Recent'), findsNWidgets(5));
    await tester.enterText(find.byType(TextField), 'Amsterdam');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Amsterdam 1'), findsOneWidget);
    expect(find.textContaining('Recent'), findsNothing);

    // The browser blurs the field on pointer down, and the rest of the page
    // rebuilds, before the click reaches the spot of the suggestion.
    final spot = tester.getCenter(find.text('Amsterdam 1'));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(app());
    await tester.tapAt(spot);
    await tester.pump();
    expect(chosen?.label, 'Amsterdam 1');
  });

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
