import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/navigation/route_tracker.dart';
import 'package:homemaps/utils/msi.dart';
import 'package:homemaps/widgets/navigation_bar.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'navigation_test.dart' show stroe;

Map<String, dynamic> gantry(LatLng p, double heading, List<String> perLane) => {
  'type': 'Feature',
  'properties': {'kind': 'msi', 'bearing': heading, 'lanes': perLane},
  'geometry': {
    'type': 'Point',
    'coordinates': [p.longitude, p.latitude],
  },
};

void main() {
  final tracker = RouteTracker(stroe());
  final points = tracker.route.points;

  ({LatLng point, double heading, double along}) onRoute(int i) {
    final position = tracker.locate(points[i]);
    return (point: points[i], heading: position.heading, along: position.along);
  }

  test('gantries above your carriageway, in order; not the opposite side', () {
    final a = onRoute(40), b = onRoute(20);
    final gantries = gantriesOnRoute(tracker, {
      'features': [
        gantry(a.point, a.heading, ['80r', 'x']),
        gantry(b.point, b.heading, ['80r', '80r']),
        // The same spot, the other direction.
        gantry(a.point, (a.heading + 180) % 360, ['50r']),
        // Far from the route.
        gantry(const LatLng(52.5, 5.0), 0, ['50r']),
        // At the same spot, but 30 m to the side (a parallel carriageway): the
        // gantry right above the route wins.
        gantry(
          LatLng(b.point.latitude + 30 / 110574, b.point.longitude),
          b.heading,
          ['90r'],
        ),
        {
          'type': 'Feature',
          'properties': {'kind': 'accident'},
          'geometry': {
            'type': 'Point',
            'coordinates': [a.point.longitude, a.point.latitude],
          },
        },
      ],
    });
    expect(gantries.map((p) => p.perLane), [
      ['80r', '80r'],
      ['80r', 'x'],
    ]);
    expect(gantries.first.along, closeTo(b.along, 1));
  });

  test('the mandatory speed of the last gantry passed', () {
    const gantries = <Gantry>[
      (along: 1000, perLane: ['80r', '80r', 'x']),
      (along: 2000, perLane: ['70', '70']), // advisory: no limit
      (along: 3000, perLane: ['70r', '50r']),
      (along: 4000, perLane: ['end', 'end']),
      (along: 5000, perLane: ['90r']),
      (along: 6000, perLane: ['', '']), // blank: that's where it ends
    ];
    expect(msiLimit(gantries, 500), isNull);
    expect(msiLimit(gantries, 1500), 80);
    expect(msiLimit(gantries, 2500), isNull);
    expect(msiLimit(gantries, 3500), 50); // the lowest
    expect(msiLimit(gantries, 4500), isNull);
    expect(msiLimit(gantries, 5500), 90);
    expect(msiLimit(gantries, 6500), isNull);
    // Too far past the last gantry: then it no longer applies.
    expect(
      msiLimit(const [
        (along: 0, perLane: ['90r']),
      ], 3500),
      isNull,
    );
  });

  test(
    'the next gantry showing something, within one and a half kilometres',
    () {
      const gantries = <Gantry>[
        (along: 1000, perLane: ['80r', 'x']),
        (along: 2000, perLane: ['', '']),
        (along: 3000, perLane: ['50r']),
      ];
      final first = nextGantry(gantries, 0)!;
      expect(first.ahead, 1000);
      expect(first.perLane, ['80r', 'x']);
      // The blank gantry comes first: then nothing until you've passed it.
      expect(nextGantry(gantries, 1200), isNull);
      expect(nextGantry(gantries, 2100)?.ahead, 900);
      expect(nextGantry(gantries, 3100), isNull);
      expect(
        nextGantry(const [
          (along: 5000, perLane: ['50r']),
        ], 0),
        isNull,
      );
    },
  );

  testWidgets('the matrix bar: per lane what it shows', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: MatrixBar(['80r', '70', 'x', '<', 'open', 'end', '']),
        ),
      ),
    );
    expect(find.text('80'), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.south_west), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(find.byIcon(Icons.block), findsOneWidget);
    // Only the mandatory one has a red ring.
    final rings = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration! as BoxDecoration).shape == BoxShape.circle,
        );
    expect(rings, hasLength(1));
  });
}
