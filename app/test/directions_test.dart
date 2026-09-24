import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/models/route.dart';
import 'package:homemaps/navigation/turn_arrow.dart';
import 'package:homemaps/utils/distance.dart';
import 'package:homemaps/utils/formatting.dart';
import 'package:homemaps/navigation/navigation_provider.dart';
import 'package:homemaps/navigation/lane_choice.dart';
import 'package:homemaps/navigation/route_tracker.dart';
import 'package:homemaps/services/valhalla_service.dart';
import 'package:homemaps/widgets/maneuver_icon.dart';
import 'package:homemaps/widgets/navigation_bar.dart';
import 'package:homemaps/widgets/step_list.dart';

import 'navigation_test.dart' show stroe;

/// De Meern -> Utrecht Science Park via the A12, A27 and A28 (junctions
/// Lunetten and Rijnsweerd), as Valhalla 3.9 returned it.
RouteOption utrecht() {
  final json = jsonDecode(
    File('test/fixtures/valhalla_utrecht.json').readAsStringSync(),
  );
  return RouteOption.fromValhalla(
    (json['trip'] as Map).cast<String, dynamic>(),
    elevationInterval: 30,
  );
}

/// The same route as `trace_route` with `format: osrm`, only the intersections
/// with lanes.
List<LaneAdvice> utrechtLanes() => ValhallaService.parseLanes(
  (jsonDecode(
    File('test/fixtures/valhalla_utrecht_lanes.json').readAsStringSync(),
  ) as Map).cast<String, dynamic>(),
);

void main() {
  test(
    'roundabout: the exit number and exit angle, same on entry and exit',
    () {
      final roundabouts = [
        for (final m in stroe().maneuvers)
          if (m.isRoundabout) m,
      ];
      expect([for (final m in roundabouts) m.type], [26, 27, 26, 27]);
      expect([for (final m in roundabouts) m.roundaboutExit], [2, 2, 2, 2]);
      // First: 288° in, 323° out -- bear right. Second: 267° in, 261°
      // out -- almost straight on.
      expect(roundabouts[0].roundaboutAngle, closeTo(35, 0.1));
      expect(roundabouts[1].roundaboutAngle, roundabouts[0].roundaboutAngle);
      expect(roundabouts[2].roundaboutAngle, closeTo(354, 0.1));
      expect(roundabouts[3].roundaboutAngle, roundabouts[2].roundaboutAngle);
    },
  );

  test('sign: exit number, road numbers, directions and junction', () {
    final m = utrecht().maneuvers;
    final exit = m.firstWhere((m) => m.type == 20).roadSign!;
    expect(exit.exit, '15');
    expect(exit.roads, ['A12']);
    expect(exit.directions, ['Utrecht']);

    final lunetten = m.firstWhere(
      (m) => m.roadSign?.roads.contains('A27') ?? false,
    );
    expect(lunetten.roadSign!.label, 'Knooppunt Lunetten');
    expect(lunetten.roadSign!.directions.first, 'Amersfoort');

    // A roundabout exit with an empty `sign` has no sign.
    expect(RoadSign.fromValhalla(const {}), isNull);
    expect(stroe().maneuvers.where((m) => m.roadSign != null), isEmpty);
  });

  test('sign: also the guide signs above the through road', () {
    final roadSign = RoadSign.fromValhalla(const {
      'guide_branch_elements': [
        {'text': 'A27'},
      ],
      'guide_toward_elements': [
        {'text': 'Almere'},
        {'text': 'Hilversum'},
      ],
      'junction_name_elements': [
        {'text': 'Knooppunt Eemnes'},
      ],
    })!;
    expect(roadSign.roads, ['A27']);
    expect(roadSign.directions, ['Almere', 'Hilversum']);
    expect(roadSign.label, 'Knooppunt Eemnes');
    // Those of the exit itself take precedence.
    expect(
      RoadSign.fromValhalla(const {
        'exit_toward_elements': [
          {'text': 'Utrecht'},
        ],
        'guide_toward_elements': [
          {'text': 'Almere'},
        ],
      })!.directions,
      ['Utrecht'],
    );
  });

  test('signpost: without a sign the road number, only at ramps', () {
    // Stroe: "Houd links aan om op Heuvelrandweg/R101 te blijven", no sign
    // and no A, N or S number.
    final m = stroe().maneuvers;
    expect(m.firstWhere((m) => m.type == 24).signpost, isNull);
    const fork = Maneuver(
      instruction: 'Houd links aan om op A27 te blijven.',
      type: 24,
      meters: 0,
      seconds: 0,
      shapeIndex: 0,
      streets: ['E 231', 'A27'],
    );
    expect(fork.signpost!.roads, ['A27']);
    // A plain turn never has a signpost.
    expect(m.firstWhere((m) => m.type == 15).signpost, isNull);
    expect(mainRoadNumber(['Rijksweg 12', 'E 30']), 'E 30');
    expect(mainRoadNumber(['Heuvelrandweg', 'R101']), isNull);
  });

  test('lanes from the OSRM response, in order along the route', () {
    final advice = utrechtLanes();
    expect(advice, isNotEmpty);
    // Just after the on-ramp onto the A12: three lanes straight on (correct),
    // three bearing right off (not).
    final a12 = advice.firstWhere((a) => a.perLane.length == 6);
    expect(
      [for (final s in a12.perLane) s.correct],
      [true, true, true, false, false, false],
    );
    expect(a12.perLane.first.directions, ['straight']);
    expect(a12.perLane.first.usage, 'straight');

    final along = RouteTracker(utrecht())
        .alongOf([for (final a in advice) a.position]);
    expect(along, everyElement(isNotNull));
    for (var i = 1; i < along.length; i++) {
      expect(along[i]!, greaterThanOrEqualTo(along[i - 1]!));
    }
  });

  Widget app(Widget child) => MaterialApp(
    locale: const Locale('nl'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets('a roundabout draws its exit, the rest is a plain icon', (
    tester,
  ) async {
    final m = stroe().maneuvers;
    await tester.pumpWidget(
      app(
        Row(
          children: [
            ManeuverIcon(m.firstWhere((m) => m.type == 26)),
            ManeuverIcon(m.firstWhere((m) => m.type == 15)),
          ],
        ),
      ),
    );
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<RoundaboutPainter>()
        .single;
    expect(painter.angle, closeTo(35, 0.1));
    expect(painter.turn, 2);
    expect(find.byIcon(Icons.turn_left), findsOneWidget);
    expect(find.byIcon(Icons.roundabout_right), findsNothing);
  });

  testWidgets('fork and exit: the branch you take, not two choices', (
    tester,
  ) async {
    final m = utrecht().maneuvers;
    await tester.pumpWidget(
      app(
        Row(
          children: [
            ManeuverIcon(m.firstWhere((m) => m.type == 23)),
            ManeuverIcon(m.firstWhere((m) => m.type == 24)),
            ManeuverIcon(m.firstWhere((m) => m.type == 20)),
          ],
        ),
      ),
    );
    final sides = [
      for (final c in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
        if (c.painter case final ForkPainter s) s.right,
    ];
    expect(sides, [true, false, true]);
    expect(find.byIcon(Icons.fork_right), findsNothing);
  });

  testWidgets('after "enter roundabout" no "exit roundabout" as the next one', (
    tester,
  ) async {
    final route = stroe();
    final entry = route.maneuvers.indexWhere((m) => m.type == 26);
    await tester.pumpWidget(
      app(
        NavigationHeader(
          NavigationState(
            route: route,
            destinations: const [],
            status: NavStatus(
              onRoute: route.points.first,
              segment: 0,
              along: 0,
              deviation: 0,
              routeHeading: 0,
              next: entry,
              toNext: 100,
              remainingMeters: 5000,
              remainingSeconds: 600,
              offRoute: false,
              arrived: false,
            ),
          ),
        ),
      ),
    );
    // After the first roundabout there's still a way to go: no "Then" anymore.
    expect(find.text('Daarna'), findsNothing);
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where((c) => c.painter is RoundaboutPainter),
      hasLength(1),
    );
  });

  testWidgets('header at an exit: sign and lanes', (tester) async {
    final route = utrecht();
    final exit = route.maneuvers.indexWhere((m) => m.type == 20);
    final status = NavStatus(
      onRoute: route.points.first,
      segment: 0,
      along: 0,
      deviation: 0,
      routeHeading: 0,
      next: exit,
      toNext: 400,
      remainingMeters: 10000,
      remainingSeconds: 600,
      offRoute: false,
      arrived: false,
    );
    await tester.pumpWidget(
      app(
        NavigationHeader(
          NavigationState(
            route: route,
            destinations: const [],
            status: status,
            lanes: (
              ahead: 350,
              atManeuver: true,
              perLane: const [
                Lane(directions: ['straight'], correct: false),
                Lane(
                  directions: ['straight', 'right'],
                  correct: true,
                  usage: 'right',
                ),
                Lane(directions: ['right'], correct: true),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(RoadSignPanel), findsOneWidget);
    expect(find.text('Afrit 15'), findsOneWidget);
    expect(find.text('A12'), findsOneWidget);
    expect(find.text('Utrecht'), findsOneWidget);
    expect(find.byType(LaneBar), findsOneWidget);
    // Of the combined lane only the direction you take.
    expect(
      find.descendant(
        of: find.byType(LaneBar),
        matching: find.byIcon(Icons.turn_right),
      ),
      findsNWidgets(2),
    );
    expect(find.bySemanticsLabel('2 goede rijstroken van 3'), findsOneWidget);
  });

  group('which lanes in the header', () {
    const fork = [
      Lane(directions: ['straight'], correct: true),
      Lane(directions: ['straight'], correct: true),
      Lane(directions: ['right'], correct: false),
    ];
    const exit = [
      Lane(directions: ['straight'], correct: false),
      Lane(directions: ['right'], correct: true),
    ];
    // An exit you must not take at 1200 m, yours at 1800 m.
    const junctions = [
      (along: 1200.0, perLane: fork),
      (along: 1800.0, perLane: exit),
    ];
    LaneChoice? at(double along, {double? kmh = 100}) => chooseLanes(
      junctions,
      along: along,
      maneuver: 1800,
      speed: kmh == null ? null : kmh / 3.6,
    );

    test('far before the exit nothing yet, not even the exit before it', () {
      expect(at(0), isNull);
      expect(at(700), isNull);
    });

    test('just before an earlier exit: that one, with its own distance', () {
      final choice = at(900)!;
      expect(choice.perLane, same(fork));
      expect(choice.atManeuver, isFalse);
      expect(choice.ahead, 300);
    });

    test('then the lanes of the exit itself', () {
      final choice = at(1250)!;
      expect(choice.perLane, same(exit));
      expect(choice.atManeuver, isTrue);
      expect(choice.ahead, 550);
    });

    test('the slower, the later', () {
      // 50 km/h: about 500 m in advance.
      expect(at(1250, kmh: 50), isNull);
      expect(at(1350, kmh: 50)!.perLane, same(exit));
      // At walking pace still at least 300 m.
      expect(at(1500, kmh: 5)!.perLane, same(exit));
      // No speed: the maximum.
      expect(at(1250, kmh: null)!.perLane, same(exit));
    });

    test('every lane correct: nothing to choose', () {
      expect(
        chooseLanes(
          [
            (
              along: 500.0,
              perLane: fork
                  .map((s) => Lane(directions: s.directions, correct: true))
                  .toList(),
            ),
          ],
          along: 400,
          maneuver: 500,
        ),
        isNull,
      );
    });
  });

  testWidgets('lanes of an earlier intersection: with distance', (
    tester,
  ) async {
    const perLane = [
      Lane(directions: ['straight'], correct: true),
      Lane(directions: ['right'], correct: false),
    ];
    await tester.pumpWidget(app(const LaneBar(perLane, ahead: 312)));
    expect(find.text('300 m'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Over 300 m: 1 goede rijstrook van 2'),
      findsOneWidget,
    );

    await tester.pumpWidget(app(const LaneBar(perLane)));
    expect(find.text('300 m'), findsNothing);
    expect(find.bySemanticsLabel('1 goede rijstrook van 2'), findsOneWidget);
  });

  testWidgets('header at a fork: briefly what you do, with the sign', (
    tester,
  ) async {
    final route = utrecht();
    final left = route.maneuvers.indexWhere((m) => m.type == 24);
    await tester.pumpWidget(
      app(
        NavigationHeader(
          NavigationState(
            route: route,
            destinations: const [],
            status: NavStatus(
              onRoute: route.points.first,
              segment: 0,
              along: 0,
              deviation: 0,
              routeHeading: 0,
              next: left,
              toNext: 15000,
              remainingMeters: 20000,
              remainingSeconds: 900,
              offRoute: false,
              arrived: false,
            ),
          ),
        ),
      ),
    );
    expect(find.text('15 km'), findsOneWidget);
    expect(find.text('Links aanhouden'), findsOneWidget);
    expect(find.text('A12'), findsOneWidget);
    expect(find.textContaining('Amersfoort'), findsOneWidget);
    expect(find.textContaining('Houd links aan'), findsNothing);
  });

  test('step list: roundabout exit and continue without their own row', () {
    final route = stroe();
    final steps = StepList.steps(route);
    // Two roundabouts: only "enter" (26) gets a row, including the stretch to
    // past the exit.
    expect(steps.where((s) => s.maneuver.type == 27), isEmpty);
    expect(steps.where((s) => s.maneuver.type == 26), hasLength(2));
    // Together still the whole route.
    expect(
      steps.fold(0.0, (sum, s) => sum + s.meters),
      closeTo(route.maneuvers.fold(0.0, (sum, m) => sum + m.meters), 1),
    );

    // En route: how far each step still is, increasing from the next one.
    final enRoute = StepList.steps(route, startIndex: 2, toNext: 120);
    expect(enRoute.first.maneuver, same(route.maneuvers[2]));
    expect(enRoute.first.meters, 120);
    expect(enRoute[1].meters, 120 + route.maneuvers[2].meters);
  });

  testWidgets('tap the header: the directions', (tester) async {
    final route = utrecht();
    var tapped = 0;
    await tester.pumpWidget(
      app(
        NavigationHeader(
          NavigationState(
            route: route,
            destinations: const [],
            status: NavStatus(
              onRoute: route.points.first,
              segment: 0,
              along: 0,
              deviation: 0,
              routeHeading: 0,
              next: 1,
              toNext: 200,
              remainingMeters: 20000,
              remainingSeconds: 900,
              offRoute: false,
              arrived: false,
            ),
          ),
          onTap: () => tapped++,
        ),
      ),
    );
    await tester.tap(find.byType(NavigationHeader));
    expect(tapped, 1);

    await tester.pumpWidget(app(SingleChildScrollView(child: StepList(route))));
    // The exit and the forks brief, with their sign.
    expect(find.text('Afslag nemen'), findsNothing);
    // Exit 2 appears once, even though Valhalla splits it in two.
    expect(find.text('Afrit nemen'), findsNWidgets(2));
    expect(find.text('Afrit 2'), findsOneWidget);
    expect(find.text('Links aanhouden'), findsOneWidget);
    expect(find.text('Afrit 15'), findsOneWidget);
    expect(find.textContaining('Sla rechtsaf naar Meerndijk'), findsOneWidget);
  });

  test('main roads: via A12 and A27, in route order', () {
    expect(mainRoads(utrecht(), max: 3), ['A12', 'A27', 'A28']);
    expect(mainRoads(utrecht()), ['A12', 'A27']);
    // Road numbers take precedence over street names.
    expect(mainRoads(stroe()), ['N344', 'N303']);
  });

  group('turn arrow', () {
    double length(List<LatLng> line) {
      var sum = 0.0;
      for (var i = 1; i < line.length; i++) {
        sum += meters(line[i - 1], line[i]);
      }
      return sum;
    }

    test('40 m before to 30 m after the turn', () {
      final route = stroe();
      final left = route.maneuvers.indexWhere((m) => m.type == 15);
      final arrow = turnArrow(route, left)!;
      expect(length(arrow), closeTo(70, 1));
      // The turn point lies on the arrow.
      final turn = route.points[route.maneuvers[left].shapeIndex];
      expect(metersToLine(turn, arrow), lessThan(1));
    });

    test('a roundabout: until past the exit', () {
      final route = stroe();
      final entry = route.maneuvers.indexWhere((m) => m.type == 26);
      final arrow = turnArrow(route, entry)!;
      final finish = route.points[route.maneuvers[entry + 1].shapeIndex];
      expect(metersToLine(finish, arrow), lessThan(1));
      expect(length(arrow), greaterThan(70));
    });

    test('no arrow at start, straight on and destination', () {
      final route = stroe();
      expect(turnArrow(route, 0), isNull);
      expect(turnArrow(route, route.maneuvers.length - 1), isNull);
      expect(hasTurnArrow(route.maneuvers.first), isFalse);
    });
  });

  test('distance: decimal comma in Dutch, rounded en route', () {
    expect(distance(2600, 'nl'), '2,6 km');
    expect(distance(2600, 'en'), '2.6 km');
    expect(distance(816), '816 m');
    expect(distance(15300, 'nl'), '15 km');
    expect(roundDistance(816), 800);
    expect(roundDistance(87), 90);

    final route = utrecht();
    final enRoute = StepList.steps(route, toNext: 816);
    expect(
      enRoute.where((s) => s.maneuver.roadSign?.exit == '2'),
      hasLength(1),
    );
  });
}
