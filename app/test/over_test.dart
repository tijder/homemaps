import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/screens/over_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  testWidgets('over: versie, bronnen en licenties', (tester) async {
    OverScreen.info = () async => PackageInfo(
      appName: 'HomeMaps',
      packageName: 'nl.homemaps',
      version: '0.4.0',
      buildNumber: '64',
    );
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OverScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Versie 0.4.0 (64)'), findsOneWidget);
    expect(find.text('OpenStreetMap'), findsOneWidget);
    expect(
      find.text('Kaartgegevens © OpenStreetMap-bijdragers'),
      findsOneWidget,
    );
    expect(find.text('Valhalla'), findsOneWidget);

    await tester.tap(find.text('Licenties'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
