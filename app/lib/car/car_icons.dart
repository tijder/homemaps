import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/route.dart';
import '../widgets/maneuver_icon.dart';

/// The icons the car templates show, drawn as PNG: the same maneuver icons as
/// the phone's header, so a roundabout shows its exit and a fork its branch.
/// Both Android Auto and CarPlay want the app to supply these images.

/// A key that is the same for the same picture, so it is drawn and sent once.
String maneuverIconKey(Maneuver m, {required bool dark}) {
  final angle = m.roundaboutAngle;
  final rounded = angle == null ? '' : (angle / 10).round() * 10;
  return 'm:${m.type}:${m.roundaboutExit ?? ''}:$rounded:${dark ? 'd' : 'l'}';
}

String lanesIconKey(List<Lane> lanes, {required bool dark}) {
  final parts = [
    for (final lane in lanes)
      '${lane.correct ? '+' : '-'}${lane.usage ?? lane.directions.join('/')}',
  ];
  return 'l:${parts.join(',')}:${dark ? 'd' : 'l'}';
}

Future<Uint8List> _toPng(ui.PictureRecorder recorder, int w, int h) async {
  final image = await recorder.endRecording().toImage(w, h);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

/// A Material icon glyph drawn on the canvas, filling [size].
void _glyph(Canvas canvas, IconData icon, Offset at, double size, Color color) {
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size,
        color: color,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    at + Offset((size - painter.width) / 2, (size - painter.height) / 2),
  );
}

/// The maneuver icon, [size] pixels square. White on dark, otherwise black:
/// the templates put it on their own background.
Future<Uint8List> maneuverPng(
  Maneuver m, {
  required bool dark,
  double size = 128,
}) {
  final color = dark ? Colors.white : Colors.black;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final painter = maneuverPainter(m, color: color);
  if (painter != null) {
    painter.paint(canvas, Size(size, size));
  } else {
    _glyph(canvas, maneuverIconData(m.type), Offset.zero, size, color);
  }
  return _toPng(recorder, size.toInt(), size.toInt());
}

/// The lane bar as one image: an arrow per lane, correct ones solid and the
/// rest dimmed, with thin dividers, as on the phone.
Future<Uint8List> lanesPng(
  List<Lane> lanes, {
  required bool dark,
  double height = 96,
}) {
  final color = dark ? Colors.white : Colors.black;
  final dim = color.withValues(alpha: 0.35);
  final laneWidth = height * 1.1;
  final width = laneWidth * lanes.length;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (final (i, lane) in lanes.indexed) {
    final x = i * laneWidth;
    if (i > 0) {
      canvas.drawLine(
        Offset(x, height * 0.15),
        Offset(x, height * 0.85),
        Paint()
          ..color = dim
          ..strokeWidth = 2,
      );
    }
    // A correct lane with more directions: only the one you take.
    final directions = lane.correct && lane.usage != null
        ? [lane.usage!]
        : lane.directions.isEmpty
        ? const ['straight']
        : lane.directions.take(2).toList();
    final glyph = directions.length > 1 ? height * 0.5 : height * 0.75;
    final total = glyph * directions.length;
    var gx = x + (laneWidth - total) / 2;
    for (final direction in directions) {
      _glyph(
        canvas,
        laneIconData(direction),
        Offset(gx, (height - glyph) / 2),
        glyph,
        lane.correct ? color : dim,
      );
      gx += glyph;
    }
  }
  return _toPng(recorder, width.ceil(), height.toInt());
}
