import 'dart:math';

import 'package:flutter/material.dart';

import '../models/route.dart';

/// The icon for Valhalla's maneuver type, for the instruction list and the
/// navigation bar.
IconData maneuverIconData(int type) => switch (type) {
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

/// The icon for a maneuver. A roundabout shows which exit you take, a fork or
/// off-ramp which branch; the rest is [maneuverIconData].
class ManeuverIcon extends StatelessWidget {
  const ManeuverIcon(this.maneuver, {super.key, this.size, this.color});

  final Maneuver maneuver;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? IconTheme.of(context).color ?? Colors.black;
    final painter = maneuverPainter(
      maneuver,
      color: color,
      text: DefaultTextStyle.of(context).style,
    );
    if (painter == null) {
      return Icon(maneuverIconData(maneuver.type), size: size, color: color);
    }
    return Semantics(
      label: maneuver.instruction,
      child: SizedBox.square(
        dimension: size ?? IconTheme.of(context).size ?? 24,
        child: CustomPaint(painter: painter),
      ),
    );
  }
}

/// The painter for a maneuver that is more than an icon: a roundabout with
/// its exit, a fork or off-ramp with its branch. Null for the rest (see
/// [maneuverIconData]). [text] is the font for the exit number.
CustomPainter? maneuverPainter(
  Maneuver maneuver, {
  required Color color,
  TextStyle? text,
}) {
  final angle = maneuver.roundaboutAngle;
  return switch (maneuver.type) {
    26 || 27 when angle != null => RoundaboutPainter(
      angle: angle,
      turn: maneuver.roundaboutExit,
      color: color,
      text: text,
    ),
    // Off-ramp/on-ramp right, keep right at a fork.
    18 || 20 || 23 => ForkPainter(right: true, color: color),
    19 || 21 || 24 => ForkPainter(right: false, color: color),
    _ => null,
  };
}

/// A fork or off-ramp: the branch you take thick and with an arrowhead, the
/// road you leave thin and dimmed. That way it reads as "right here", not as
/// two choices.
class ForkPainter extends CustomPainter {
  const ForkPainter({required this.right, required this.color});

  /// The branch you take goes to the right (otherwise to the left).
  final bool right;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final x = size.width / 2 + (right ? -s * 0.12 : s * 0.12);
    final splits = Offset(x, size.height * 0.56);
    // Straight on: the road you leave.
    canvas.drawLine(
      splits,
      Offset(x, size.height * 0.06),
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..strokeWidth = s * 0.07
        ..strokeCap = StrokeCap.round,
    );

    final side = right ? 1.0 : -1.0;
    final end = Offset(x + side * s * 0.34, size.height * 0.16);
    final route = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(x, size.height * 0.97)
      ..lineTo(splits.dx, splits.dy)
      ..quadraticBezierTo(x, size.height * 0.38, end.dx, end.dy);
    canvas.drawPath(path, route);

    // The arrowhead, in the direction the curve ends.
    final direction = Offset(end.dx - x, end.dy - size.height * 0.38);
    final length = direction.distance;
    final r = direction / length;
    final perpendicular = Offset(-r.dy, r.dx);
    final top = end + r * (s * 0.08);
    final basis = end - r * (s * 0.08);
    final arrow = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(
        (basis + perpendicular * (s * 0.12)).dx,
        (basis + perpendicular * (s * 0.12)).dy,
      )
      ..lineTo(
        (basis - perpendicular * (s * 0.12)).dx,
        (basis - perpendicular * (s * 0.12)).dy,
      )
      ..close();
    canvas.drawPath(arrow, Paint()..color = color);
  }

  @override
  bool shouldRepaint(ForkPainter old) =>
      old.right != right || old.color != color;
}

/// A roundabout from above: you come from the bottom, drive counterclockwise
/// (right-hand traffic) and leave at [angle] (clockwise from straight on).
class RoundaboutPainter extends CustomPainter {
  const RoundaboutPainter({
    required this.angle,
    this.turn,
    required this.color,
    this.text,
  });

  final double angle;
  final int? turn;
  final Color color;

  /// For the font of the exit number.
  final TextStyle? text;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = s * 0.24;
    final thick = s * 0.11;
    final thin = s * 0.05;
    // Angle (0 = top, clockwise) to a point at distance r.
    Offset point(double degrees, double r) {
      final rad = degrees * pi / 180;
      return center + Offset(sin(rad) * r, -cos(rad) * r);
    }

    final ring = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = thin;
    canvas.drawCircle(center, radius, ring);

    final route = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thick
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // On from the bottom, then counterclockwise to the exit. A U-turn (nearly
    // 180) goes all the way around the ring.
    var sweep = (180 - angle) % 360;
    if (sweep < 10) sweep += 360;
    final path = Path()
      ..moveTo(center.dx, size.height * 0.97)
      ..lineTo(point(180, radius).dx, point(180, radius).dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        // Canvas angles: 0 = right, clockwise. Bottom is 90°; counterclockwise
        // is negative.
        pi / 2,
        -sweep * pi / 180,
        false,
      );
    final off = point(angle, s * 0.46);
    path.lineTo(off.dx, off.dy);
    canvas.drawPath(path, route);

    // An arrowhead at the end of the exit.
    final rad = angle * pi / 180;
    final direction = Offset(sin(rad), -cos(rad));
    final perpendicular = Offset(-direction.dy, direction.dx);
    final point0 = off + direction * (s * 0.06);
    final arrow = Path()
      ..moveTo(point0.dx, point0.dy)
      ..lineTo(
        (off - direction * (s * 0.1) + perpendicular * (s * 0.12)).dx,
        (off - direction * (s * 0.1) + perpendicular * (s * 0.12)).dy,
      )
      ..lineTo(
        (off - direction * (s * 0.1) - perpendicular * (s * 0.12)).dx,
        (off - direction * (s * 0.1) - perpendicular * (s * 0.12)).dy,
      )
      ..close();
    canvas.drawPath(arrow, Paint()..color = color);

    if (turn case final number?) {
      final digit = TextPainter(
        text: TextSpan(
          text: '$number',
          style: (text ?? const TextStyle()).copyWith(
            color: color,
            fontSize: s * 0.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      digit.paint(canvas, center - Offset(digit.width / 2, digit.height / 2));
    }
  }

  @override
  bool shouldRepaint(RoundaboutPainter old) =>
      old.angle != angle ||
      old.turn != turn ||
      old.color != color ||
      old.text != text;
}

/// The arrow for one direction of a lane (as OSRM names them).
IconData laneIconData(String direction) => switch (direction) {
  'slight right' => Icons.turn_slight_right,
  'right' => Icons.turn_right,
  'sharp right' => Icons.turn_sharp_right,
  'slight left' => Icons.turn_slight_left,
  'left' => Icons.turn_left,
  'sharp left' => Icons.turn_sharp_left,
  'uturn' => Icons.u_turn_left,
  _ => Icons.straight,
};
