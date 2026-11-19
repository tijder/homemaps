import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/models/place.dart';
import 'package:homemaps/navigation/navigation_provider.dart';
import 'package:homemaps/navigation/route_tracker.dart';
import 'package:homemaps/widgets/navigation_bar.dart';

import 'navigation_test.dart' show fix, stroe;

void main() {
  final route = stroe();
  final status = RouteTracker(route).track(fix(route.points[3]));
  NavigationState nav({bool gpsLost = false, bool rerouteFailed = false}) =>
      NavigationState(
        route: route,
        destinations: [Place(label: 'Voorthuizen', point: route.points.last)],
        status: status,
        gpsLost: gpsLost,
        rerouteFailed: rerouteFailed,
      );

  Widget app(Widget child, {double width = 360}) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );

  testWidgets('the footer fits a small phone, with one line per text', (
    tester,
  ) async {
    var more = 0;
    await tester.pumpWidget(
      app(
        NavigationFooter(
          nav(),
          onStop: () {},
          onMute: (_) {},
          onMore: () => more++,
          attention: true,
        ),
        // 360 wide, less the margin around the footer.
        width: 344,
      ),
    );
    // An overflow would have failed the test by now.
    final arrival = tester.getSize(find.textContaining('Arrive'));
    expect(arrival.height, lessThan(40));
    await tester.tap(find.byTooltip('More'));
    expect(more, 1);
    expect(find.byTooltip('Mute'), findsOneWidget);
  });

  testWidgets('the header says when there is no fix', (tester) async {
    await tester.pumpWidget(app(NavigationHeader(nav(gpsLost: true))));
    expect(find.text('No GPS signal'), findsOneWidget);
    await tester.pumpWidget(app(NavigationHeader(nav())));
    expect(find.text('No GPS signal'), findsNothing);
  });

  testWidgets('the header says when the route shown is still the old one', (
    tester,
  ) async {
    await tester.pumpWidget(app(NavigationHeader(nav(rerouteFailed: true))));
    expect(find.textContaining('still the old one'), findsOneWidget);
  });
}
