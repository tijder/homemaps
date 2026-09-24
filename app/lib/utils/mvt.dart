import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:maplibre_gl/maplibre_gl.dart';

/// A point from a vector tile, with its properties (class, subclass, name,
/// ...).
typedef TilePoint = ({LatLng point, Map<String, Object?> properties});

/// The points of one layer from a Mapbox vector tile (protobuf). Only what
/// "search along the route" needs: point geometry and properties; lines and
/// polygons are skipped.
///
/// No bit operations on large numbers: compiled to JavaScript those are 32 bits
/// (see decodePolyline).
List<TilePoint> pointsFromTile(
  Uint8List data, {
  required String layer,
  required int z,
  required int x,
  required int y,
}) {
  final out = <TilePoint>[];
  final tile = _Reader(data);
  while (!tile.done) {
    final (field, kind) = tile.key();
    if (field == 3 && kind == 2) {
      _layer(tile.message(), layer, z, x, y, out);
    } else {
      tile.skip(kind);
    }
  }
  return out;
}

void _layer(
  _Reader l,
  String wanted,
  int z,
  int x,
  int y,
  List<TilePoint> out,
) {
  String? name;
  var extent = 4096;
  final keys = <String>[];
  final values = <Object?>[];
  final features = <_Reader>[];
  while (!l.done) {
    final (field, kind) = l.key();
    switch ((field, kind)) {
      case (1, 2):
        name = l.text();
      case (2, 2):
        features.add(l.message());
      case (3, 2):
        keys.add(l.text());
      case (4, 2):
        values.add(_value(l.message()));
      case (5, 0):
        extent = l.varint();
      default:
        l.skip(kind);
    }
  }
  if (name != wanted) return;
  final n = pow(2, z).toDouble();
  for (final f in features) {
    var type = 0;
    List<int> tags = const [], geometry = const [];
    while (!f.done) {
      final (field, kind) = f.key();
      switch ((field, kind)) {
        case (2, 2):
          tags = f.packed();
        case (3, 0):
          type = f.varint();
        case (4, 2):
          geometry = f.packed();
        default:
          f.skip(kind);
      }
    }
    if (type != 1 || geometry.length < 3) continue; // points only
    final props = <String, Object?>{};
    for (var i = 0; i + 1 < tags.length; i += 2) {
      if (tags[i] < keys.length && tags[i + 1] < values.length) {
        props[keys[tags[i]]] = values[tags[i + 1]];
      }
    }
    // Command MoveTo (1) with a count, then pairs of zigzag numbers.
    final command = geometry[0];
    final count = command ~/ 8;
    var px = 0, py = 0;
    for (var i = 0; i < count && 2 + 2 * i < geometry.length; i++) {
      px += _zigzag(geometry[1 + 2 * i]);
      py += _zigzag(geometry[2 + 2 * i]);
      final lon = (x + px / extent) / n * 360 - 180;
      final mercator = pi * (1 - 2 * (y + py / extent) / n);
      final lat = atan((exp(mercator) - exp(-mercator)) / 2) * 180 / pi;
      out.add((point: LatLng(lat, lon), properties: props));
    }
  }
}

int _zigzag(int n) => n.isOdd ? -(n + 1) ~/ 2 : n ~/ 2;

Object? _value(_Reader l) {
  Object? value;
  while (!l.done) {
    final (field, kind) = l.key();
    switch ((field, kind)) {
      case (1, 2):
        value = l.text();
      case (2, 5):
        value = l.float32();
      case (3, 1):
        value = l.float64();
      case (4, 0) || (5, 0):
        value = l.varint();
      case (6, 0):
        value = _zigzag(l.varint());
      case (7, 0):
        value = l.varint() != 0;
      default:
        l.skip(kind);
    }
  }
  return value;
}

/// Reads protobuf, just enough for vector tiles.
class _Reader {
  _Reader(this.data, [this.pos = 0, int? end]) : end = end ?? data.length;

  final Uint8List data;
  int pos;
  final int end;

  bool get done => pos >= end;

  int varint() {
    var value = 0, factor = 1;
    while (true) {
      final byte = data[pos++];
      value += (byte & 0x7f) * factor;
      if (byte < 0x80) return value;
      factor *= 128;
    }
  }

  (int, int) key() {
    final s = varint();
    return (s ~/ 8, s % 8);
  }

  _Reader message() {
    final length = varint();
    final sub = _Reader(data, pos, pos + length);
    pos += length;
    return sub;
  }

  String text() {
    final s = message();
    return utf8.decode(
      Uint8List.sublistView(data, s.pos, s.end),
      allowMalformed: true,
    );
  }

  List<int> packed() {
    final s = message();
    final out = <int>[];
    while (!s.done) {
      out.add(s.varint());
    }
    return out;
  }

  double float32() {
    final value = ByteData.sublistView(
      data,
      pos,
      pos + 4,
    ).getFloat32(0, Endian.little);
    pos += 4;
    return value;
  }

  double float64() {
    final value = ByteData.sublistView(
      data,
      pos,
      pos + 8,
    ).getFloat64(0, Endian.little);
    pos += 8;
    return value;
  }

  void skip(int kind) {
    switch (kind) {
      case 0:
        varint();
      case 1:
        pos += 8;
      case 2:
        pos += varint();
      case 5:
        pos += 4;
      default:
        throw FormatException('unknown protobuf wire type $kind');
    }
  }
}
