import 'dart:math';

import 'package:flutter/material.dart';

import '../models/route.dart';

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

/// Het pictogram bij een manoeuvre. Een rotonde laat zien welke uitrit je
/// neemt, een splitsing of afrit welke tak; de rest is [manoeuvrePictogram].
class ManoeuvreIcoon extends StatelessWidget {
  const ManoeuvreIcoon(this.manoeuvre, {super.key, this.size, this.color});

  final Manoeuvre manoeuvre;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final kleur = color ?? IconTheme.of(context).color ?? Colors.black;
    final hoek = manoeuvre.rotondeHoek;
    final CustomPainter? schilder = switch (manoeuvre.type) {
      26 || 27 when hoek != null => RotondeSchilder(
        hoek: hoek,
        afslag: manoeuvre.rotondeAfslag,
        kleur: kleur,
        tekst: DefaultTextStyle.of(context).style,
      ),
      // Afrit/oprit rechts, splitsing rechts aanhouden.
      18 || 20 || 23 => SplitsingSchilder(rechts: true, kleur: kleur),
      19 || 21 || 24 => SplitsingSchilder(rechts: false, kleur: kleur),
      _ => null,
    };
    if (schilder == null) {
      return Icon(manoeuvrePictogram(manoeuvre.type), size: size, color: color);
    }
    return Semantics(
      label: manoeuvre.instructie,
      child: SizedBox.square(
        dimension: size ?? IconTheme.of(context).size ?? 24,
        child: CustomPaint(painter: schilder),
      ),
    );
  }
}

/// Een splitsing of afrit: de tak die je neemt dik en met een pijlpunt, de weg
/// die je laat liggen dun en gedimd. Zo leest het als "hier rechts", niet als
/// twee keuzes.
class SplitsingSchilder extends CustomPainter {
  const SplitsingSchilder({required this.rechts, required this.kleur});

  /// De tak die je neemt gaat naar rechts (anders naar links).
  final bool rechts;
  final Color kleur;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final x = size.width / 2 + (rechts ? -s * 0.12 : s * 0.12);
    final splits = Offset(x, size.height * 0.56);
    // Rechtdoor: de weg die je laat liggen.
    canvas.drawLine(
      splits,
      Offset(x, size.height * 0.06),
      Paint()
        ..color = kleur.withValues(alpha: 0.35)
        ..strokeWidth = s * 0.07
        ..strokeCap = StrokeCap.round,
    );

    final kant = rechts ? 1.0 : -1.0;
    final eind = Offset(x + kant * s * 0.34, size.height * 0.16);
    final route = Paint()
      ..color = kleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final pad = Path()
      ..moveTo(x, size.height * 0.97)
      ..lineTo(splits.dx, splits.dy)
      ..quadraticBezierTo(x, size.height * 0.38, eind.dx, eind.dy);
    canvas.drawPath(pad, route);

    // De pijlpunt, in de richting waarin de bocht eindigt.
    final richting = Offset(eind.dx - x, eind.dy - size.height * 0.38);
    final lengte = richting.distance;
    final r = richting / lengte;
    final dwars = Offset(-r.dy, r.dx);
    final top = eind + r * (s * 0.08);
    final basis = eind - r * (s * 0.08);
    final pijl = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo((basis + dwars * (s * 0.12)).dx, (basis + dwars * (s * 0.12)).dy)
      ..lineTo((basis - dwars * (s * 0.12)).dx, (basis - dwars * (s * 0.12)).dy)
      ..close();
    canvas.drawPath(pijl, Paint()..color = kleur);
  }

  @override
  bool shouldRepaint(SplitsingSchilder oud) =>
      oud.rechts != rechts || oud.kleur != kleur;
}

/// Een rotonde van bovenaf: je komt van onderen, rijdt tegen de klok in (rechts
/// rijden) en gaat eraf bij [hoek] (met de klok mee vanaf rechtdoor).
class RotondeSchilder extends CustomPainter {
  const RotondeSchilder({
    required this.hoek,
    this.afslag,
    required this.kleur,
    this.tekst,
  });

  final double hoek;
  final int? afslag;
  final Color kleur;

  /// Voor het lettertype van het afslagnummer.
  final TextStyle? tekst;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final midden = Offset(size.width / 2, size.height / 2);
    final straal = s * 0.24;
    final dik = s * 0.11;
    final dun = s * 0.05;
    // Hoek (0 = boven, met de klok mee) naar een punt op afstand r.
    Offset punt(double graden, double r) {
      final rad = graden * pi / 180;
      return midden + Offset(sin(rad) * r, -cos(rad) * r);
    }

    final ring = Paint()
      ..color = kleur.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = dun;
    canvas.drawCircle(midden, straal, ring);

    final route = Paint()
      ..color = kleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = dik
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Van onderen erop, dan tegen de klok in tot de uitrit. Een U-bocht (vrijwel
    // 180) gaat de hele ring rond.
    var boog = (180 - hoek) % 360;
    if (boog < 10) boog += 360;
    final pad = Path()
      ..moveTo(midden.dx, size.height * 0.97)
      ..lineTo(punt(180, straal).dx, punt(180, straal).dy)
      ..arcTo(
        Rect.fromCircle(center: midden, radius: straal),
        // Canvas-hoeken: 0 = rechts, met de klok mee. Onder is 90°; tegen de
        // klok in is negatief.
        pi / 2,
        -boog * pi / 180,
        false,
      );
    final uit = punt(hoek, s * 0.46);
    pad.lineTo(uit.dx, uit.dy);
    canvas.drawPath(pad, route);

    // Een pijlpunt aan het eind van de uitrit.
    final rad = hoek * pi / 180;
    final richting = Offset(sin(rad), -cos(rad));
    final dwars = Offset(-richting.dy, richting.dx);
    final punt0 = uit + richting * (s * 0.06);
    final pijl = Path()
      ..moveTo(punt0.dx, punt0.dy)
      ..lineTo(
        (uit - richting * (s * 0.1) + dwars * (s * 0.12)).dx,
        (uit - richting * (s * 0.1) + dwars * (s * 0.12)).dy,
      )
      ..lineTo(
        (uit - richting * (s * 0.1) - dwars * (s * 0.12)).dx,
        (uit - richting * (s * 0.1) - dwars * (s * 0.12)).dy,
      )
      ..close();
    canvas.drawPath(pijl, Paint()..color = kleur);

    if (afslag case final nummer?) {
      final cijfer = TextPainter(
        text: TextSpan(
          text: '$nummer',
          style: (tekst ?? const TextStyle()).copyWith(
            color: kleur,
            fontSize: s * 0.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      cijfer.paint(
        canvas,
        midden - Offset(cijfer.width / 2, cijfer.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(RotondeSchilder oud) =>
      oud.hoek != hoek ||
      oud.afslag != afslag ||
      oud.kleur != kleur ||
      oud.tekst != tekst;
}

/// Het pijltje voor één richting van een rijstrook (zoals OSRM ze noemt).
IconData rijstrookPictogram(String richting) => switch (richting) {
  'slight right' => Icons.turn_slight_right,
  'right' => Icons.turn_right,
  'sharp right' => Icons.turn_sharp_right,
  'slight left' => Icons.turn_slight_left,
  'left' => Icons.turn_left,
  'sharp left' => Icons.turn_sharp_left,
  'uturn' => Icons.u_turn_left,
  _ => Icons.straight,
};
