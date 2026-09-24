import 'package:flutter/material.dart';

/// The elevation profile of a route: one line, filled, with min and max.
class ElevationProfile extends StatelessWidget {
  const ElevationProfile({super.key, required this.elevations});

  final List<double> elevations;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final low = elevations.reduce((a, b) => a < b ? a : b);
    final high = elevations.reduce((a, b) => a > b ? a : b);
    final style = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      height: 90,
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${high.round()} m', style: style),
              Text('${low.round()} m', style: style),
            ],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: CustomPaint(
              painter: _Painter(elevations, low, high, color),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.elevations, this.low, this.high, this.color);

  final List<double> elevations;
  final double low, high;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // A flat route (the Netherlands) must not fill the whole height with a few
    // meters of noise: the range is at least 20 m.
    final range = (high - low) < 20 ? 20.0 : high - low;
    final line = Path();
    for (var i = 0; i < elevations.length; i++) {
      final x = size.width * i / (elevations.length - 1);
      final y = size.height * (1 - (elevations[i] - low) / range);
      i == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Painter old) =>
      old.elevations != elevations || old.color != color;
}
