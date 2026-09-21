import 'package:flutter/material.dart';

/// Het hoogteprofiel van een route: één lijn, gevuld, met min en max erbij.
class Hoogteprofiel extends StatelessWidget {
  const Hoogteprofiel({super.key, required this.hoogtes});

  final List<double> hoogtes;

  @override
  Widget build(BuildContext context) {
    final kleur = Theme.of(context).colorScheme.primary;
    final laag = hoogtes.reduce((a, b) => a < b ? a : b);
    final hoog = hoogtes.reduce((a, b) => a > b ? a : b);
    final stijl = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      height: 90,
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${hoog.round()} m', style: stijl),
              Text('${laag.round()} m', style: stijl),
            ],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: CustomPaint(
              painter: _Schilder(hoogtes, laag, hoog, kleur),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }
}

class _Schilder extends CustomPainter {
  _Schilder(this.hoogtes, this.laag, this.hoog, this.kleur);

  final List<double> hoogtes;
  final double laag, hoog;
  final Color kleur;

  @override
  void paint(Canvas canvas, Size size) {
    // Een vlakke route (Nederland) mag niet de hele hoogte vullen met ruis van
    // een paar meter: het bereik is minstens 20 m.
    final bereik = (hoog - laag) < 20 ? 20.0 : hoog - laag;
    final lijn = Path();
    for (var i = 0; i < hoogtes.length; i++) {
      final x = size.width * i / (hoogtes.length - 1);
      final y = size.height * (1 - (hoogtes[i] - laag) / bereik);
      i == 0 ? lijn.moveTo(x, y) : lijn.lineTo(x, y);
    }
    final vlak = Path.from(lijn)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(vlak, Paint()..color = kleur.withValues(alpha: 0.18));
    canvas.drawPath(
      lijn,
      Paint()
        ..color = kleur
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Schilder oud) =>
      oud.hoogtes != hoogtes || oud.kleur != kleur;
}
