import 'dart:math';

import '../models/route.dart';

/// The lanes shown in the header, how far away that intersection is, and
/// whether it's the intersection of the maneuver in the header (otherwise it
/// lies before it).
typedef LaneChoice = ({double ahead, List<Lane> perLane, bool atManeuver});

/// This many seconds before the maneuver the lanes appear...
const laneSeconds = 35.0;

/// ...but no earlier than this many meters before it...
const laneMax = 1500.0;

/// ...and no later than this many meters before it.
const laneMin = 300.0;

/// An intersection before the maneuver (a fork, a lane that ends) only
/// appears this shortly in advance, with its own distance shown.
const laneBetween = 400.0;

/// This close to the maneuver an intersection belongs to the maneuver itself.
const _atMargin = 50.0;

/// Which lanes belong in the header, or null.
///
/// As in Google or Apple Maps: the lanes of the turn in the header, only just
/// before it. An intersection before it where the lane you take matters too
/// takes precedence once it's close. That one gets its distance shown, so it
/// doesn't look like the turn in the header.
///
/// [junctions] in order along the route; [along] is where you are and
/// [maneuver] where the next maneuver is, both along the route; [speed] in
/// m/s.
LaneChoice? chooseLanes(
  List<({double along, List<Lane> perLane})> junctions, {
  required double along,
  required double maneuver,
  double? speed,
}) {
  final ahead = speed == null
      ? laneMax
      : (speed * laneSeconds).clamp(laneMin, laneMax);
  ({double along, List<Lane> perLane})? between, at;
  for (final junction in junctions) {
    if (junction.along < along) continue;
    if (junction.along > maneuver + 10) break;
    // One lane, or every lane correct: then there's nothing to choose.
    if (junction.perLane.length < 2 ||
        junction.perLane.every((s) => s.correct)) {
      continue;
    }
    if (junction.along >= maneuver - _atMargin) {
      at = junction;
    } else {
      between ??= junction;
    }
  }
  if (between != null && between.along - along <= min(ahead, laneBetween)) {
    return (
      ahead: between.along - along,
      perLane: between.perLane,
      atManeuver: false,
    );
  }
  if (at != null && maneuver - along <= ahead) {
    return (ahead: at.along - along, perLane: at.perLane, atManeuver: true);
  }
  return null;
}
