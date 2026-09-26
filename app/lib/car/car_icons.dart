import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/route.dart';
import '../widgets/maneuver_icon.dart';

/// The icons the car templates show, drawn as PNG: the same maneuver icons as
/// the phone's header, so a roundabout shows its exit and a fork its branch.
/// Both Android Auto and CarPlay want the app to supply these images. They
/// are white: the car's panel is our own blue (see `CarPlaySceneDelegate` and
/// `NavigationScreen`), whatever the car's day or night mode.

/// A key that is the same for the same picture, so it is drawn and sent once.
String maneuverIconKey(Maneuver m) {
  final angle = m.roundaboutAngle;
  final rounded = angle == null ? '' : (angle / 10).round() * 10;
  return 'm:${m.type}:${m.roundaboutExit ?? ''}:$rounded';
}

/// [ahead]: the distance shown left of the lanes, if the junction isn't the
/// maneuver's own.
String lanesIconKey(List<Lane> lanes, {String? ahead}) {
  final parts = [
    for (final lane in lanes)
      '${lane.correct ? '+' : '-'}${lane.usage ?? lane.directions.join('/')}',
  ];
  return 'l:${parts.join(',')}:${ahead ?? ''}';
}

String signIconKey(RoadSign sign) =>
    's:${sign.exit ?? ''}:${sign.roads.join('/')}:'
    '${sign.directions.join('/')}:${sign.label ?? ''}';

String matrixIconKey(List<String> perLane) => 'x:${perLane.join(',')}';

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

TextPainter _text(
  String text,
  double size,
  Color color, {
  FontWeight weight = FontWeight.w700,
}) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(fontSize: size, color: color, fontWeight: weight),
  ),
  textDirection: TextDirection.ltr,
)..layout();

/// The maneuver icon, [size] pixels square, white.
Future<Uint8List> maneuverPng(Maneuver m, {double size = 128}) {
  const color = Colors.white;
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
/// rest dimmed, with thin dividers, as on the phone. With [ahead] ("400 m")
/// on the left: the junction lies before the maneuver.
Future<Uint8List> lanesPng(
  List<Lane> lanes, {
  String? ahead,
  double height = 96,
}) {
  const color = Colors.white;
  final dim = color.withValues(alpha: 0.35);
  final laneWidth = height * 1.1;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  var left = 0.0;
  if (ahead != null) {
    final painter = _text(ahead, height * 0.4, color);
    painter.paint(canvas, Offset(height * 0.1, (height - painter.height) / 2));
    left = painter.width + height * 0.3;
  }
  for (final (i, lane) in lanes.indexed) {
    final x = left + i * laneWidth;
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
  final width = left + laneWidth * lanes.length;
  return _toPng(recorder, width.ceil(), height.toInt());
}

/// The sign at an exit as the phone's `RoadSignPanel`: a blue board with the
/// exit number, the road shields (A red, E green, N yellow) and the
/// directions. [exitText] is "Exit 12" in the driver's language. [height] in
/// pixels; the car shows it at a third of that, inline with the instruction.
Future<Uint8List> signPng(
  RoadSign sign, {
  required String? exitText,
  double height = 72,
}) {
  const blue = Color(0xFF0A4C9A);
  final s = height / 24;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final parts = <(TextPainter, Color, Color?)>[
    if (exitText != null) (_text(exitText, 11 * s, blue), Colors.white, null),
    for (final road in sign.roads.take(2))
      if (road.startsWith('A') || road.startsWith('E'))
        (
          _text(road, 11 * s, Colors.white),
          road.startsWith('E')
              ? const Color(0xFF00843D)
              : const Color(0xFFD2232A),
          null,
        )
      else if (road.startsWith('N'))
        (_text(road, 11 * s, Colors.black), const Color(0xFFFFD200), null)
      else
        (_text(road, 11 * s, Colors.white), blue, null),
  ];
  final directions = sign.directions.isNotEmpty
      ? sign.directions.take(3).join(' · ')
      : sign.label;
  final direction = directions == null
      ? null
      : _text(directions, 12 * s, Colors.white, weight: FontWeight.w600);
  var width = 8 * s;
  for (final (painter, _, _) in parts) {
    width += painter.width + 12 * s + 6 * s;
  }
  if (direction != null) width += direction.width + 6 * s;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      Radius.circular(8 * s),
    ),
    Paint()..color = blue,
  );
  var x = 8 * s;
  for (final (painter, background, _) in parts) {
    final box = Rect.fromLTWH(
      x,
      (height - painter.height) / 2 - 2 * s,
      painter.width + 12 * s,
      painter.height + 4 * s,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(4 * s)),
      Paint()..color = background,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, Radius.circular(4 * s)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * s,
    );
    painter.paint(canvas, Offset(x + 6 * s, (height - painter.height) / 2));
    x += box.width + 6 * s;
  }
  direction?.paint(canvas, Offset(x, (height - direction.height) / 2));
  return _toPng(recorder, width.ceil(), height.toInt());
}

/// The next gantry's matrix signs as the phone's `MatrixBar`: a black square
/// per lane with the speed (a red ring when mandatory), a red cross, an arrow
/// to the next lane, a green arrow or an end-of-restrictions sign. [scale]
/// pixels per phone pixel.
Future<Uint8List> matrixPng(List<String> perLane, {double scale = 3}) {
  const red = Color(0xFFD32F2F);
  final s = scale;
  final box = 38 * s, gap = 6 * s, pad = 12 * s, vpad = 6 * s;
  final width = pad * 2 + box * perLane.length + gap * (perLane.length - 1);
  final height = box + vpad * 2;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      Radius.circular(10 * s),
    ),
    Paint()..color = const Color(0xFF263238),
  );
  for (final (i, lane) in perLane.indexed) {
    final x = pad + i * (box + gap);
    final rect = Rect.fromLTWH(x, vpad, box, box);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(4 * s)),
      Paint()..color = Colors.black,
    );
    final glyph = 28 * s;
    final at = Offset(x + (box - glyph) / 2, vpad + (box - glyph) / 2);
    switch (lane) {
      case 'x':
        _glyph(canvas, Icons.close, at, glyph, red);
      case '<':
        _glyph(canvas, Icons.south_west, at, glyph, Colors.white);
      case '>':
        _glyph(canvas, Icons.south_east, at, glyph, Colors.white);
      case 'open':
        _glyph(
          canvas,
          Icons.arrow_downward,
          at,
          glyph,
          const Color(0xFF43A047),
        );
      case 'end':
        _glyph(canvas, Icons.block, at, glyph, Colors.white70);
      case '':
        break;
      default:
        final mandatory = lane.endsWith('r');
        final number = mandatory ? lane.substring(0, lane.length - 1) : lane;
        final painter = _text(number, 15 * s, Colors.white);
        painter.paint(
          canvas,
          rect.center - Offset(painter.width / 2, painter.height / 2),
        );
        if (mandatory) {
          canvas.drawCircle(
            rect.center,
            17 * s - 1.5 * s,
            Paint()
              ..color = red
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3 * s,
          );
        }
    }
  }
  return _toPng(recorder, width.ceil(), height.ceil());
}
