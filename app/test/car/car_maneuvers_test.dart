import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/car/car_api.g.dart';
import 'package:homemaps/car/car_icons.dart';
import 'package:homemaps/car/car_maneuvers.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/models/route.dart';

import '../navigation_test.dart' show stroe;

Maneuver maneuver(int type, {int? exit, double? angle, RoadSign? sign}) =>
    Maneuver(
      instruction: 'x',
      type: type,
      meters: 100,
      seconds: 10,
      shapeIndex: 0,
      endShapeIndex: 1,
      streets: const ['A12'],
      roundaboutExit: exit,
      roundaboutAngle: angle,
      roadSign: sign,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l = lookupAppLocalizations(const Locale('en'));

  test('every Valhalla type has a car type; unknown is straight', () {
    expect(carManeuverType(maneuver(10)), CarManeuverType.right);
    expect(carManeuverType(maneuver(15)), CarManeuverType.left);
    expect(carManeuverType(maneuver(26)), CarManeuverType.roundabout);
    expect(carManeuverType(maneuver(27)), CarManeuverType.roundaboutExit);
    expect(carManeuverType(maneuver(20)), CarManeuverType.offRampRight);
    expect(carManeuverType(maneuver(38)), CarManeuverType.mergeLeft);
    expect(carManeuverType(maneuver(4)), CarManeuverType.destination);
    expect(carManeuverType(maneuver(99)), CarManeuverType.straight);
  });

  test('the sign and the short action come along', () {
    final m = maneuver(
      20,
      sign: const RoadSign(exit: '15', roads: ['A12'], directions: ['Utrecht']),
    );
    final car = carManeuver(m, l, iconKey: 'k', metersToNext: 500);
    expect(car.shortAction, 'Take the exit');
    expect(car.sign?.exit, '15');
    expect(car.sign?.directions, ['Utrecht']);
    expect(
      carManeuver(maneuver(10), l, iconKey: 'k', metersToNext: 1).shortAction,
      isNull,
    );
  });

  test('"then": the maneuver right after, skipping the roundabout exit', () {
    final route = stroe();
    final m = route.maneuvers;
    // A maneuver followed within 300 m by another.
    final close = m.indexWhere((x) => x.meters < 300 && x.type != 26);
    expect(afterwardsIndex(route, close), close + 1);
    final far = m.indexWhere((x) => x.meters > 300);
    expect(afterwardsIndex(route, far), isNull);
    final roundabout = m.indexWhere((x) => x.type == 26);
    if (roundabout >= 0 && m[roundabout + 1].type == 27) {
      final after = afterwardsIndex(route, roundabout);
      expect(after, anyOf(isNull, roundabout + 2));
    }
  });

  test('icon keys: the same picture is the same key', () {
    expect(
      maneuverIconKey(maneuver(26, exit: 2, angle: 91), dark: false),
      maneuverIconKey(maneuver(26, exit: 2, angle: 93), dark: false),
    );
    expect(
      maneuverIconKey(maneuver(26, exit: 2, angle: 91), dark: false),
      isNot(maneuverIconKey(maneuver(26, exit: 3, angle: 91), dark: false)),
    );
    expect(
      maneuverIconKey(maneuver(10), dark: true),
      isNot(maneuverIconKey(maneuver(10), dark: false)),
    );
  });

  test('icons are PNGs', () async {
    final turn = await maneuverPng(maneuver(10), dark: false);
    expect(turn.sublist(1, 4), 'PNG'.codeUnits);
    final roundabout = await maneuverPng(
      maneuver(26, exit: 2, angle: 90),
      dark: true,
    );
    expect(roundabout.sublist(1, 4), 'PNG'.codeUnits);
    final lanes = await lanesPng(const [
      Lane(directions: ['left'], correct: false),
      Lane(directions: ['straight', 'right'], correct: true, usage: 'right'),
    ], dark: false);
    expect(lanes.sublist(1, 4), 'PNG'.codeUnits);
  });
}
