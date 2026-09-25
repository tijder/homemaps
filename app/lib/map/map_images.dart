import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The images the map needs, drawn as PNG: the same on the phone and in the
/// car.

Future<Uint8List> _png(void Function(Canvas canvas) draw, double size) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

/// The head of the turn arrow: a white triangle with a dark border, pointing
/// up (north); the layer rotates it with the bearing. 48 px, drawn at 2x, so
/// the layer shows it at scale 0.5.
Future<Uint8List> arrowHeadPng() {
  const size = 48.0;
  return _png((canvas) {
    final path = Path()
      ..moveTo(size / 2, 5)
      ..lineTo(size - 5, size - 3)
      ..lineTo(5, size - 3)
      ..close();
    canvas
      ..drawPath(
        path,
        Paint()
          ..color = const Color(0xFF0D47A1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawPath(path, Paint()..color = Colors.white);
  }, size);
}

/// Your position in the car: a blue dot with a white border and a wedge in
/// the direction of travel, pointing up; the layer rotates it. 64 px at 2x.
Future<Uint8List> locationPuckPng() {
  const size = 64.0;
  return _png((canvas) {
    const center = Offset(size / 2, size / 2);
    final wedge = Path()
      ..moveTo(size / 2, 2)
      ..lineTo(size / 2 + 14, size / 2 - 4)
      ..lineTo(size / 2 - 14, size / 2 - 4)
      ..close();
    canvas
      ..drawPath(wedge, Paint()..color = const Color(0xFF1565C0))
      ..drawCircle(center, 18, Paint()..color = Colors.white)
      ..drawCircle(center, 14, Paint()..color = const Color(0xFF1565C0));
  }, size);
}

/// A speed camera, red light camera or average speed check on the map: a
/// dark rounded square with [icon] in white. 48 px at 2x.
Future<Uint8List> cameraPng(IconData icon) {
  const size = 48.0;
  return _png((canvas) {
    final square = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3, 3, size - 6, size - 6),
      const Radius.circular(9),
    );
    canvas
      ..drawRRect(square, Paint()..color = Colors.white)
      ..drawRRect(square.deflate(3), Paint()..color = const Color(0xFF263238));
    final glyph = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 28,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    glyph.paint(
      canvas,
      Offset((size - glyph.width) / 2, (size - glyph.height) / 2),
    );
  }, size);
}
