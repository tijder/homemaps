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

  group('what a search ends in', () {
    Widget app(PhotonService photon, {ValueChanged<Place>? onChosen}) =>
        ProviderScope(
          overrides: [photonProvider.overrideWithValue(photon)],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SearchField(
                label: 'Search',
                place: null,
                onChosen: onChosen ?? (_) {},
                onCleared: () {},
              ),
            ),
          ),
        );

    testWidgets('nothing found says so, with what was searched for', (
      tester,
    ) async {
      await tester.pumpWidget(app(_ScriptedPhoton((_) => const [])));
      await tester.enterText(find.byType(TextField), 'qqqq');
      await tester.pump();
      // Typed, not answered yet: busy.
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('Nothing found for “qqqq”'), findsOneWidget);
    });

    testWidgets('a failed search says so, and a tap tries again', (
      tester,
    ) async {
      var fail = true;
      final photon = _ScriptedPhoton((text) {
        if (fail) throw DioException(requestOptions: RequestOptions());
        return [Place(label: text, point: const LatLng(52, 5))];
      });
      await tester.pumpWidget(app(photon));
      await tester.enterText(find.byType(TextField), 'ede');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.textContaining('Search is not available'), findsOneWidget);
      fail = false;
      await tester.tap(find.textContaining('Search is not available'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Search is not available'), findsNothing);
      expect(find.widgetWithText(ListTile, 'ede'), findsOneWidget);
    });

    testWidgets('Enter before the results are in takes the first one', (
      tester,
    ) async {
      Place? chosen;
      final photon = _ScriptedPhoton(
        (text) => [Place(label: 'Ede', point: const LatLng(52, 5))],
      );
      await tester.pumpWidget(app(photon, onChosen: (p) => chosen = p));
      await tester.enterText(find.byType(TextField), 'ede');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump();
      expect(chosen?.label, 'Ede');
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  testWidgets('the floating bar scrolls when the suggestions do not fit', (
    tester,
  ) async {
    final photon = _ScriptedPhoton(
      (text) => [
        for (var i = 0; i < 10; i++)
          Place(
            label: '$text $i',
            description: 'Somewhere',
            point: LatLng(52.0 + i, 5.0),
          ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [photonProvider.overrideWithValue(photon)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            // What is left above an on-screen keyboard on a phone.
            body: SizedBox(
              height: 300,
              child: Column(
                children: [
                  Flexible(
                    child: SearchField(
                      floating: true,
                      label: 'Search',
                      place: null,
                      onChosen: (_) {},
                      onCleared: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'ede');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    // No overflow (that would fail the test), and the last one is reachable.
    await tester.scrollUntilVisible(
      find.text('ede 9'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('ede 9'), findsOneWidget);
  });
}

class _ScriptedPhoton extends PhotonService {
  _ScriptedPhoton(this.answer) : super(Dio(), 'http://photon.test');

  final List<Place> Function(String text) answer;

  @override
  Future<List<Place>> search(
    String text, {
    LatLng? near,
    CancelToken? cancel,
  }) async => answer(text);
}
