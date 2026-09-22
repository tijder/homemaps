import 'package:maplibre_gl/maplibre_gl.dart';

/// Valhalla's "encoded polyline" met zes decimalen (Google's formaat kent er vijf).
List<LatLng> decodeerPolyline(String tekst, {int decimalen = 6}) {
  final factor = _macht10(decimalen);
  final punten = <LatLng>[];
  var index = 0, lat = 0, lon = 0;
  while (index < tekst.length) {
    for (var as = 0; as < 2; as++) {
      var resultaat = 0, schuif = 0, byte = 0;
      do {
        byte = tekst.codeUnitAt(index++) - 63;
        resultaat |= (byte & 0x1f) << schuif;
        schuif += 5;
      } while (byte >= 0x20);
      // Niet `~(resultaat >> 1)`: gecompileerd naar JavaScript is het resultaat van
      // een bit-operatie een niet-negatief 32-bits getal, dus een negatieve stap
      // werd daar ruim vier miljard en de lijn schoot recht naar het noorden. In
      // de VM en in wasm gaat het goed, en daarom vingen de tests het niet.
      final half = resultaat >> 1;
      final delta = (resultaat & 1) != 0 ? -half - 1 : half;
      if (as == 0) {
        lat += delta;
      } else {
        lon += delta;
      }
    }
    punten.add(LatLng(lat / factor, lon / factor));
  }
  return punten;
}

/// Het omgekeerde van [decodeerPolyline]. Alleen gewone rekenkunde, geen
/// bit-operaties op mogelijk negatieve getallen: zie de opmerking daar over
/// JavaScript.
String codeerPolyline(List<LatLng> punten, {int decimalen = 6}) {
  final factor = _macht10(decimalen);
  final uit = StringBuffer();
  void getal(int waarde) {
    // Zigzag: 0, -1, 1, -2, 2 ... -> 0, 1, 2, 3, 4 ...
    var v = waarde < 0 ? -2 * waarde - 1 : 2 * waarde;
    while (v >= 0x20) {
      uit.writeCharCode(0x20 + v % 32 + 63);
      v = v ~/ 32;
    }
    uit.writeCharCode(v + 63);
  }

  var lat = 0, lon = 0;
  for (final punt in punten) {
    final nieuwLat = (punt.latitude * factor).round();
    final nieuwLon = (punt.longitude * factor).round();
    getal(nieuwLat - lat);
    getal(nieuwLon - lon);
    lat = nieuwLat;
    lon = nieuwLon;
  }
  return uit.toString();
}

double _macht10(int n) {
  var waarde = 1.0;
  for (var i = 0; i < n; i++) {
    waarde *= 10;
  }
  return waarde;
}
