import '../l10n/app_localizations.dart';
import '../models/route.dart';
import '../widgets/navigation_bar.dart' show shortAction;
import 'car_api.g.dart';

/// Valhalla's maneuver types as the car knows them, grouped like the phone's
/// icons (see `maneuverIconData`). Native maps these on to Android Auto's
/// `Maneuver.TYPE_*` and CarPlay's `CPManeuverType`.
CarManeuverType carManeuverType(Maneuver m) => switch (m.type) {
  1 || 2 || 3 => CarManeuverType.depart,
  4 => CarManeuverType.destination,
  5 => CarManeuverType.destinationRight,
  6 => CarManeuverType.destinationLeft,
  7 => CarManeuverType.nameChange,
  8 => CarManeuverType.straight,
  9 => CarManeuverType.slightRight,
  10 => CarManeuverType.right,
  11 => CarManeuverType.sharpRight,
  12 => CarManeuverType.uturnRight,
  13 => CarManeuverType.uturnLeft,
  14 => CarManeuverType.sharpLeft,
  15 => CarManeuverType.left,
  16 => CarManeuverType.slightLeft,
  17 => CarManeuverType.onRampStraight,
  18 => CarManeuverType.onRampRight,
  19 => CarManeuverType.onRampLeft,
  20 => CarManeuverType.offRampRight,
  21 => CarManeuverType.offRampLeft,
  22 => CarManeuverType.keepStraight,
  23 => CarManeuverType.keepRight,
  24 => CarManeuverType.keepLeft,
  25 => CarManeuverType.merge,
  37 => CarManeuverType.mergeRight,
  38 => CarManeuverType.mergeLeft,
  26 => CarManeuverType.roundabout,
  27 => CarManeuverType.roundaboutExit,
  28 => CarManeuverType.ferryEnter,
  29 => CarManeuverType.ferryExit,
  _ => CarManeuverType.straight,
};

CarRoadSign? carRoadSign(RoadSign? sign) => sign == null
    ? null
    : CarRoadSign(
        exit: sign.exit,
        roads: sign.roads,
        directions: sign.directions,
        label: sign.label,
      );

List<CarLane> carLanes(List<Lane> lanes) => [
  for (final lane in lanes)
    CarLane(
      directions: lane.directions,
      correct: lane.correct,
      usage: lane.usage,
    ),
];

/// The maneuver for the car, without the distance and icons: the bridge adds
/// those.
CarManeuver carManeuver(
  Maneuver m,
  AppLocalizations l, {
  required String iconKey,
  required double metersToNext,
  List<CarManeuver> then = const [],
  List<Lane>? lanes,
  String? lanesIconKey,
  double? lanesAhead,
}) => CarManeuver(
  type: carManeuverType(m),
  instruction: m.instruction,
  shortAction: m.signpost == null ? null : shortAction(m, l),
  streets: m.streets,
  roundaboutExit: m.roundaboutExit,
  roundaboutAngle: m.roundaboutAngle,
  sign: carRoadSign(m.signpost),
  iconKey: iconKey,
  metersToNext: metersToNext,
  then: then,
  lanes: lanes == null ? null : carLanes(lanes),
  lanesIconKey: lanesIconKey,
  lanesAhead: lanesAhead,
);

/// If the maneuver after [index] comes within this many meters, the car shows
/// it too (as the phone's header does).
const afterwardsWithin = 300.0;

/// The index of the maneuver to show as "then", or null. After "enter
/// roundabout" comes "exit roundabout" with the same exit: that is already in
/// the icon, so then the one after it.
int? afterwardsIndex(RouteOption route, int index) {
  final maneuvers = route.maneuvers;
  var afterwards = index + 1;
  var between = maneuvers[index].meters;
  if (afterwards < maneuvers.length &&
      maneuvers[index].type == 26 &&
      maneuvers[afterwards].type == 27) {
    between += maneuvers[afterwards].meters;
    afterwards++;
  }
  return afterwards < maneuvers.length && between < afterwardsWithin
      ? afterwards
      : null;
}
