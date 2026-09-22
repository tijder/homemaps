import 'package:flutter/material.dart';

/// Het pictogram bij Valhalla's manoeuvretype, voor de instructielijst en de
/// navigatiebalk.
IconData manoeuvrePictogram(int type) => switch (type) {
  1 || 2 || 3 => Icons.trip_origin,
  4 || 5 || 6 => Icons.place,
  9 => Icons.turn_slight_right,
  10 => Icons.turn_right,
  11 => Icons.turn_sharp_right,
  12 => Icons.u_turn_right,
  13 => Icons.u_turn_left,
  14 => Icons.turn_sharp_left,
  15 => Icons.turn_left,
  16 => Icons.turn_slight_left,
  18 || 20 => Icons.ramp_right,
  19 || 21 => Icons.ramp_left,
  23 => Icons.fork_right,
  24 => Icons.fork_left,
  25 => Icons.merge,
  26 || 27 => Icons.roundabout_right,
  28 || 29 => Icons.directions_boat,
  _ => Icons.straight,
};
