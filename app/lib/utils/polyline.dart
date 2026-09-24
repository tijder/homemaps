import 'package:maplibre_gl/maplibre_gl.dart';

/// Valhalla's "encoded polyline" with six decimals (Google's format has five).
List<LatLng> decodePolyline(String text, {int decimals = 6}) {
  final factor = _pow10(decimals);
  final points = <LatLng>[];
  var index = 0, lat = 0, lon = 0;
  while (index < text.length) {
    for (var axis = 0; axis < 2; axis++) {
      var result = 0, shift = 0, byte = 0;
      do {
        byte = text.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      // Not `~(result >> 1)`: compiled to JavaScript the result of a bit
      // operation is a non-negative 32-bit number, so a negative step became
      // over four billion there and the line shot straight north. In the VM and
      // in wasm it works, which is why the tests didn't catch it.
      final half = result >> 1;
      final delta = (result & 1) != 0 ? -half - 1 : half;
      if (axis == 0) {
        lat += delta;
      } else {
        lon += delta;
      }
    }
    points.add(LatLng(lat / factor, lon / factor));
  }
  return points;
}

/// The inverse of [decodePolyline]. Only plain arithmetic, no bit operations
/// on possibly negative numbers: see the comment there about JavaScript.
String encodePolyline(List<LatLng> points, {int decimals = 6}) {
  final factor = _pow10(decimals);
  final out = StringBuffer();
  void writeNumber(int value) {
    // Zigzag: 0, -1, 1, -2, 2 ... -> 0, 1, 2, 3, 4 ...
    var v = value < 0 ? -2 * value - 1 : 2 * value;
    while (v >= 0x20) {
      out.writeCharCode(0x20 + v % 32 + 63);
      v = v ~/ 32;
    }
    out.writeCharCode(v + 63);
  }

  var lat = 0, lon = 0;
  for (final point in points) {
    final newLat = (point.latitude * factor).round();
    final newLon = (point.longitude * factor).round();
    writeNumber(newLat - lat);
    writeNumber(newLon - lon);
    lat = newLat;
    lon = newLon;
  }
  return out.toString();
}

double _pow10(int n) {
  var value = 1.0;
  for (var i = 0; i < n; i++) {
    value *= 10;
  }
  return value;
}
