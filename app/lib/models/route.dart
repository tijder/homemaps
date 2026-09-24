import 'package:maplibre_gl/maplibre_gl.dart';

import '../utils/polyline.dart';

class Maneuver {
  const Maneuver({
    required this.instruction,
    required this.type,
    required this.meters,
    required this.seconds,
    required this.shapeIndex,
    int? endShapeIndex,
    this.streets = const [],
    this.voiceEarly,
    this.voiceImminent,
    this.voiceAfter,
    this.withNext = false,
    this.roundaboutExit,
    this.roundaboutAngle,
    this.roadSign,
  }) : endShapeIndex = endShapeIndex ?? shapeIndex;

  final String instruction;

  /// Valhalla's maneuver type (1 = start, 4 = destination, 10 = right, ...).
  final int type;
  final double meters;
  final double seconds;

  /// Where in [RouteOption.points] this maneuver starts and ends.
  final int shapeIndex;
  final int endShapeIndex;

  /// The street (or road numbers) you drive on after the maneuver.
  final List<String> streets;

  /// Valhalla's spoken phrases, already in the request's language: well in
  /// advance ("Turn left onto X."), just before (with "Then ..." when the next
  /// one is close) and after ("Continue for 400 meters.").
  final String? voiceEarly;
  final String? voiceImminent;
  final String? voiceAfter;

  /// [voiceImminent] already mentions the next maneuver ("Then, in 400 meters,
  /// ...").
  final bool withNext;

  /// At a roundabout (26 enter, 27 exit): which exit, and the angle of the
  /// exit relative to where you entered (0 = straight on, 90 = right,
  /// 270 = left), clockwise.
  final int? roundaboutExit;
  final double? roundaboutAngle;

  /// What the signposts say (exit number, road numbers, directions).
  final RoadSign? roadSign;

  bool get isRoundabout => type == 26 || type == 27;

  /// On- or off-ramp, fork or merge: where the signposts matter.
  bool get isSignposted =>
      (type >= 17 && type <= 25) || type == 37 || type == 38;

  /// The sign at an on- or off-ramp, fork or merge lane. If the route has no
  /// sign, the road number you end up on ("A27"), as Google and Apple Maps do
  /// too.
  RoadSign? get signpost {
    if (!isSignposted) return null;
    if (roadSign != null) return roadSign;
    final road = mainRoadNumber(streets);
    return road == null ? null : RoadSign(roads: [road]);
  }

  /// Destination (4) or a waypoint along the way (also 4, or 5/6 right/left).
  bool get isDestination => type >= 4 && type <= 6;
}

/// Roundabout enter (26) and exit (27) belong together: the exit number is on
/// the 26, the direction you leave in on the 27. Both get the same.
({int? turn, double angle})? _roundabout(
  List<Map<String, dynamic>> raw,
  int i,
) {
  final type = raw[i]['type'];
  int enter, leave;
  if (type == 26) {
    enter = i;
    leave = i + 1;
    while (leave < raw.length && raw[leave]['type'] != 27) {
      leave++;
    }
    if (leave == raw.length) return null;
  } else if (type == 27) {
    leave = i;
    enter = i - 1;
    while (enter >= 0 && raw[enter]['type'] != 26) {
      enter--;
    }
    if (enter < 0) return null;
  } else {
    return null;
  }
  final before = raw[enter]['bearing_before'],
      after = raw[leave]['bearing_after'];
  if (before is! num || after is! num) return null;
  return (
    turn: (raw[enter]['roundabout_exit_count'] as num?)?.toInt(),
    angle: (after - before + 360) % 360.0,
  );
}

/// A road number ("A27", "N228", "S100", "E 30"), not a street name.
bool isRoadNumber(String label) => RegExp(r'^[ANSE] ?\d+$').hasMatch(label);

/// The road number on the signs: an A, N or S road first, an E number only if
/// there's nothing else. Null if there's no number.
String? mainRoadNumber(List<String> names) =>
    names.where((n) => isRoadNumber(n) && !n.startsWith('E')).firstOrNull ??
    names.where(isRoadNumber).firstOrNull;

/// The roads a route mostly follows, for "via A12, A27": the meters summed per
/// road (the road number, otherwise the name), the longest [max], in route
/// order. Road numbers go first; a road under 5% of the route doesn't count.
List<String> mainRoads(RouteOption route, {int max = 2}) {
  final meters = <String, double>{};
  for (final m in route.maneuvers) {
    if (m.streets.isEmpty) continue;
    final road = mainRoadNumber(m.streets) ?? m.streets.first;
    meters[road] = (meters[road] ?? 0) + m.meters;
  }
  final enough = [
    for (final e in meters.entries)
      if (e.value >= route.meters * 0.05) e,
  ];
  int numberFirst(MapEntry<String, double> a, MapEntry<String, double> b) {
    final na = isRoadNumber(a.key), nb = isRoadNumber(b.key);
    if (na != nb) return na ? -1 : 1;
    return b.value.compareTo(a.value);
  }

  final chosen = {for (final e in (enough..sort(numberFirst)).take(max)) e.key};
  // The map keeps the order in which the roads first appear.
  return [
    for (final road in meters.keys)
      if (chosen.contains(road)) road,
  ];
}

/// The signposts at a maneuver, as Valhalla gives them in `sign`.
class RoadSign {
  const RoadSign({
    this.exit,
    this.roads = const [],
    this.directions = const [],
    this.label,
  });

  /// The exit number ("15").
  final String? exit;

  /// Road numbers ("A12", "N228").
  final List<String> roads;

  /// Places ("Utrecht", "Amersfoort").
  final List<String> directions;

  /// The name of an interchange or exit ("Knooppunt Lunetten").
  final String? label;

  /// Null if it's blank.
  static RoadSign? fromValhalla(Object? sign) {
    if (sign is! Map) return null;
    List<String> texts(String key) {
      final out = <String>[];
      for (final e in (sign[key] as List? ?? const [])) {
        final text = e is Map ? e['text'] : null;
        if (text is String && text.isNotEmpty && !out.contains(text)) {
          out.add(text);
        }
      }
      return out;
    }

    // The signs at the exit come first; otherwise those above the through road
    // (OSM `destination` on the main carriageway) or the interchange's name.
    List<String> firstOf(String exit, String guide) {
      final out = texts(exit);
      return out.isNotEmpty ? out : texts(guide);
    }

    final exit = texts('exit_number_elements');
    final label = firstOf('exit_name_elements', 'junction_name_elements');
    final roadSign = RoadSign(
      exit: exit.firstOrNull,
      roads: firstOf('exit_branch_elements', 'guide_branch_elements'),
      directions: firstOf('exit_toward_elements', 'guide_toward_elements'),
      label: label.firstOrNull,
    );
    return roadSign.exit == null &&
            roadSign.roads.isEmpty &&
            roadSign.directions.isEmpty &&
            roadSign.label == null
        ? null
        : roadSign;
  }
}

/// One lane at an intersection, counted left to right.
class Lane {
  const Lane({required this.directions, required this.correct, this.usage});

  /// As OSRM names them: "straight", "slight right", "left", "uturn", ...
  final List<String> directions;

  /// This lane keeps you on the route.
  final bool correct;

  /// Which of [directions] you take here, if the lane has several.
  final String? usage;
}

/// Lanes at an intersection on the route.
typedef LaneAdvice = ({LatLng position, List<Lane> perLane});

class RouteOption {
  const RouteOption({
    required this.meters,
    required this.seconds,
    required this.points,
    required this.maneuvers,
    required this.elevations,
    required this.elevationInterval,
    required this.hasToll,
    required this.hasFerry,
    this.normalSeconds,
  });

  final double meters;
  final double seconds;
  final List<LatLng> points;
  final List<Maneuver> maneuvers;

  /// Elevation in meters, every [elevationInterval] meters along the route.
  /// Empty if the server has no elevation data.
  final List<double> elevations;
  final double elevationInterval;
  final bool hasToll;
  final bool hasFerry;

  /// The same route without current traffic; null if unknown (no live traffic
  /// requested, or the server didn't return it).
  final double? normalSeconds;

  /// How much longer it takes now due to jams and congestion; zero if it's fine.
  double get delay => normalSeconds == null
      ? 0
      : (seconds - normalSeconds!).clamp(0, double.infinity);

  RouteOption withNormalTime(double? seconds) => RouteOption(
    meters: meters,
    seconds: this.seconds,
    points: points,
    maneuvers: maneuvers,
    elevations: elevations,
    elevationInterval: elevationInterval,
    hasToll: hasToll,
    hasFerry: hasFerry,
    normalSeconds: seconds,
  );

  double get ascent => _sum((difference) => difference > 0 ? difference : 0);
  double get descent => _sum((difference) => difference < 0 ? -difference : 0);

  double _sum(double Function(double) part) {
    var total = 0.0;
    for (var i = 1; i < elevations.length; i++) {
      total += part(elevations[i] - elevations[i - 1]);
    }
    return total;
  }

  /// One `trip` from Valhalla's response. A route with waypoints has several
  /// legs; they are strung together here.
  factory RouteOption.fromValhalla(
    Map<String, dynamic> trip, {
    required double elevationInterval,
  }) {
    final summary = (trip['summary'] as Map).cast<String, dynamic>();
    final points = <LatLng>[];
    final maneuvers = <Maneuver>[];
    final elevations = <double>[];
    for (final leg in (trip['legs'] as List).cast<Map<String, dynamic>>()) {
      final offset = points.length;
      points.addAll(decodePolyline(leg['shape'] as String));
      final raw = (leg['maneuvers'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final (i, m) in raw.indexed) {
        final roundabout = _roundabout(raw, i);
        maneuvers.add(
          Maneuver(
            instruction: m['instruction'] as String? ?? '',
            type: (m['type'] as num?)?.toInt() ?? 0,
            meters: ((m['length'] as num?)?.toDouble() ?? 0) * 1000,
            seconds: (m['time'] as num?)?.toDouble() ?? 0,
            shapeIndex:
                offset + ((m['begin_shape_index'] as num?)?.toInt() ?? 0),
            endShapeIndex:
                offset + ((m['end_shape_index'] as num?)?.toInt() ?? 0),
            streets: [
              for (final label in (m['street_names'] as List? ?? const []))
                label as String,
            ],
            voiceEarly: m['verbal_transition_alert_instruction'] as String?,
            voiceImminent: m['verbal_pre_transition_instruction'] as String?,
            voiceAfter: m['verbal_post_transition_instruction'] as String?,
            withNext: m['verbal_multi_cue'] == true,
            roundaboutExit: roundabout?.turn,
            roundaboutAngle: roundabout?.angle,
            roadSign: RoadSign.fromValhalla(m['sign']),
          ),
        );
      }
      elevations.addAll(
        (leg['elevation'] as List? ?? const []).map(
          (h) => (h as num).toDouble(),
        ),
      );
    }
    return RouteOption(
      meters: (summary['length'] as num).toDouble() * 1000,
      seconds: (summary['time'] as num).toDouble(),
      points: points,
      maneuvers: maneuvers,
      elevations: elevations,
      elevationInterval: elevationInterval,
      hasToll: summary['has_toll'] == true,
      hasFerry: summary['has_ferry'] == true,
    );
  }
}
