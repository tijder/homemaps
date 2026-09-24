import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/models/profile.dart';
import 'package:homemaps/models/route.dart';
import 'package:homemaps/navigation/announcer.dart';
import 'package:homemaps/navigation/route_tracker.dart';
import 'package:homemaps/providers/location.dart';
import 'package:homemaps/utils/distance.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Stroe (Heetkamperweg) -> Voorthuizen, as Valhalla returned it.
RouteOption stroe() {
  final json = jsonDecode(
    File('test/fixtures/valhalla_stroe.json').readAsStringSync(),
  );
  return RouteOption.fromValhalla(
    (json['trip'] as Map).cast<String, dynamic>(),
    elevationInterval: 30,
  );
}

/// Points every [step] metres along the line, plus the end point.
List<LatLng> along(List<LatLng> line, double step) {
  final out = [line.first];
  var remaining = step;
  for (var i = 1; i < line.length; i++) {
    var a = line[i - 1];
    final b = line[i];
    var stretch = meters(a, b);
    while (stretch >= remaining) {
      final t = remaining / stretch;
      a = LatLng(
        a.latitude + t * (b.latitude - a.latitude),
        a.longitude + t * (b.longitude - a.longitude),
      );
      out.add(a);
      stretch -= remaining;
      remaining = step;
    }
    remaining -= stretch;
  }
  return out..add(line.last);
}

LocationFix fix(LatLng point, {double speed = 13, double accuracy = 5}) =>
    LocationFix(
      point: point,
      time: DateTime(2026),
      accuracy: accuracy,
      speed: speed,
    );

/// Shifted [meter] to the east (at 52° a degree of longitude is ~68 km).
LatLng east(LatLng p, double meter) => LatLng(
  p.latitude,
  p.longitude + meter / (111320 * cos(p.latitude * pi / 180)),
);

void main() {
  final route = stroe();

  test('the maneuvers get the spoken sentences and streets', () {
    final left = route.maneuvers[1];
    expect(left.voiceEarly, 'Links afslaan naar Houtbeekweg.');
    expect(left.voiceImminent, 'Links afslaan naar Houtbeekweg.');
    expect(left.voiceAfter, '700 meter doorgaan.');
    expect(left.streets, ['Houtbeekweg']);
    expect(left.endShapeIndex, greaterThan(left.shapeIndex));
    expect(route.maneuvers.last.isDestination, isTrue);
  });

  test('along the route: forward, never off route, arrived at the end', () {
    final tracker = RouteTracker(route);
    final begin = tracker.track(fix(route.points.first));
    // Without a jam the remainder at departure is the whole travel time.
    expect(
      begin.remainingSeconds,
      closeTo(route.seconds, route.seconds * 0.02),
    );
    expect(begin.remainingMeters, closeTo(route.meters, route.meters * 0.02));
    var previous = begin;
    for (final point in along(route.points, 25).skip(1)) {
      final status = tracker.track(fix(point));
      expect(status.offRoute, isFalse);
      expect(status.along, greaterThanOrEqualTo(previous.along - 1));
      expect(status.next, greaterThanOrEqualTo(previous.next));
      previous = status;
    }
    expect(previous.arrived, isTrue);
    expect(previous.next, route.maneuvers.length - 1);
  });

  test('noise beside the road is no deviation, three times far away is', () {
    final tracker = RouteTracker(route);
    final points = along(route.points, 25);
    for (final point in points.take(40)) {
      tracker.track(fix(point));
    }
    // 25 m off with an accuracy of 10 m: simply on the route.
    expect(
      tracker.track(fix(east(points[40], 25), accuracy: 10)).offRoute,
      isFalse,
    );
    final far = [for (var i = 41; i < 44; i++) east(points[i], 150)];
    expect(tracker.track(fix(far[0])).offRoute, isFalse);
    expect(tracker.track(fix(far[1])).offRoute, isFalse);
    expect(tracker.track(fix(far[2])).offRoute, isTrue);
    // Back on the road: fine again.
    expect(tracker.track(fix(points[45])).offRoute, isFalse);
  });

  List<String> drive(Profile profile, double speed) {
    final tracker = RouteTracker(route);
    final announcer = Announcer(
      route,
      profile,
      withDistance: (m, sentence) => 'In ${m.round()} m: $sentence',
    );
    return [
      for (final point in along(route.points, 10))
        ...announcer.at(tracker.track(fix(point, speed: speed)), speed),
    ];
  }

  test('every sentence once, in route order', () {
    final sentences = drive(Profile.car, 14);
    expect(sentences.first, route.maneuvers.first.voiceImminent);
    expect(sentences.last, 'Aangekomen op je bestemming.');
    // Every turn gets its "imminent" sentence.
    for (final m in route.maneuvers.skip(1)) {
      expect(sentences, contains(m.voiceImminent), reason: m.instruction);
    }
    // No sentence twice in a row (the same text may occur at two
    // different turns).
    for (var i = 1; i < sentences.length; i++) {
      expect(sentences[i], isNot(sentences[i - 1]));
    }
  });

  test('after a short stretch no "early": too late, only "imminent"', () {
    // Wolweg is 40 m; the turn onto Tolnegenweg after it has no time for an
    // announcement well in advance.
    final sentences = drive(Profile.car, 14);
    final tolnegenweg = route.maneuvers[3];
    expect(tolnegenweg.streets, ['Tolnegenweg']);
    expect(
      sentences.where((z) => z == tolnegenweg.voiceImminent),
      hasLength(1),
    );
    expect(
      sentences.where((z) => z.startsWith('In ') && z.contains('Tolnegenweg')),
      isEmpty,
    );
  });

  test('what the departure already mentioned is not announced early again', () {
    // "Daarna, over 400 meter, Links afslaan naar Houtbeekweg."
    expect(route.maneuvers.first.withNext, isTrue);
    final sentences = drive(Profile.car, 14);
    expect(
      sentences.where((z) => z.startsWith('In ')).first,
      isNot(contains('Houtbeekweg')),
    );
  });

  test('early with the distance included', () {
    final sentences = drive(Profile.car, 14);
    final early = sentences.where((z) => z.startsWith('In ')).toList();
    expect(early, isNotEmpty);
    for (final sentence in early) {
      final m = int.parse(
        RegExp(r'In (\d+) m').firstMatch(sentence)!.group(1)!,
      );
      // In the window: between 60% and 100% of 35 s at 14 m/s (490 m).
      expect(m, inInclusiveRange(290, 490));
    }
  });

  test('bike announces later than car', () {
    String identity(double m, String sentence) => sentence;
    final car = Announcer(route, Profile.car, withDistance: identity);
    final bike = Announcer(route, Profile.bike, withDistance: identity);
    expect(bike.earlyDistance(5), lessThan(car.earlyDistance(5)));
    expect(car.earlyDistance(33), 1155);
    expect(car.imminentDistance(0), 60);
  });

  group('parallel road right next to the route', () {
    // West along "Houtbeekweg", 40 m north along "Wolweg", and then west along
    // "Tolnegenweg" -- parallel to the first, 40 m beside it.
    const lat = 52.19, lon = 5.70;
    const north = 40 / 111320;
    const west = 600 / (111320 * 0.6122); // 600 m at 52°
    final bend = LatLng(lat, lon - west);
    final line = [
      const LatLng(lat, lon),
      bend,
      LatLng(lat + north, lon - west),
      LatLng(lat + north, lon - 2 * west),
    ];
    final route = RouteOption(
      meters: 1240,
      seconds: 100,
      points: line,
      maneuvers: [
        const Maneuver(
          instruction: 'start',
          type: 1,
          meters: 600,
          seconds: 48,
          shapeIndex: 0,
          endShapeIndex: 1,
        ),
        const Maneuver(
          instruction: 'right',
          type: 10,
          meters: 40,
          seconds: 4,
          shapeIndex: 1,
          endShapeIndex: 2,
        ),
        const Maneuver(
          instruction: 'left',
          type: 15,
          meters: 600,
          seconds: 48,
          shapeIndex: 2,
          endShapeIndex: 3,
        ),
        const Maneuver(
          instruction: 'arrive',
          type: 4,
          meters: 0,
          seconds: 0,
          shapeIndex: 3,
          endShapeIndex: 3,
        ),
      ],
      elevations: const [],
      elevationInterval: 30,
      hasToll: false,
      hasFerry: false,
    );

    test('missed the turn and went straight: quickly off route', () {
      final tracker = RouteTracker(route);
      // Straight on along the first road, 15 m per fix, until 300 m past the turn.
      final straight = along([
        const LatLng(lat, lon),
        LatLng(lat, lon - 1.5 * west),
      ], 15);
      var pastBend = 0;
      NavStatus? status;
      for (final point in straight) {
        status = tracker.track(fix(point, speed: 15));
        if (point.longitude < bend.longitude) pastBend++;
        if (status.offRoute) break;
      }
      expect(status!.offRoute, isTrue);
      // Within just over 100 m after the turn (without the limit: only after 300 m).
      expect(pastBend, lessThanOrEqualTo(8));
    });

    test('turn taken: simply on the route, until the end', () {
      final tracker = RouteTracker(route);
      NavStatus? status;
      for (final point in along(line, 15)) {
        status = tracker.track(fix(point, speed: 15));
        expect(status.offRoute, isFalse);
      }
      expect(status!.arrived, isTrue);
    });
  });
}
