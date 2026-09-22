import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:maplibre_gl/maplibre_gl.dart';

/// Een punt uit een vectortegel, met zijn eigenschappen (class, subclass,
/// name, ...).
typedef TegelPunt = ({LatLng punt, Map<String, Object?> eigenschappen});

/// De punten van één laag uit een Mapbox-vectortegel (protobuf). Alleen wat
/// "zoeken langs de route" nodig heeft: puntgeometrie en eigenschappen; lijnen
/// en vlakken worden overgeslagen.
///
/// Geen bit-operaties op grote getallen: gecompileerd naar JavaScript zijn die
/// 32 bits (zie decodeerPolyline).
List<TegelPunt> puntenUitTegel(
  Uint8List data, {
  required String laag,
  required int z,
  required int x,
  required int y,
}) {
  final uit = <TegelPunt>[];
  final tegel = _Lezer(data);
  while (!tegel.klaar) {
    final (veld, soort) = tegel.sleutel();
    if (veld == 3 && soort == 2) {
      _laag(tegel.stuk(), laag, z, x, y, uit);
    } else {
      tegel.overslaan(soort);
    }
  }
  return uit;
}

void _laag(_Lezer l, String gezocht, int z, int x, int y, List<TegelPunt> uit) {
  String? naam;
  var omvang = 4096;
  final sleutels = <String>[];
  final waarden = <Object?>[];
  final features = <_Lezer>[];
  while (!l.klaar) {
    final (veld, soort) = l.sleutel();
    switch ((veld, soort)) {
      case (1, 2):
        naam = l.tekst();
      case (2, 2):
        features.add(l.stuk());
      case (3, 2):
        sleutels.add(l.tekst());
      case (4, 2):
        waarden.add(_waarde(l.stuk()));
      case (5, 0):
        omvang = l.varint();
      default:
        l.overslaan(soort);
    }
  }
  if (naam != gezocht) return;
  final n = pow(2, z).toDouble();
  for (final f in features) {
    var type = 0;
    List<int> labels = const [], geometrie = const [];
    while (!f.klaar) {
      final (veld, soort) = f.sleutel();
      switch ((veld, soort)) {
        case (2, 2):
          labels = f.ingepakt();
        case (3, 0):
          type = f.varint();
        case (4, 2):
          geometrie = f.ingepakt();
        default:
          f.overslaan(soort);
      }
    }
    if (type != 1 || geometrie.length < 3) continue; // alleen punten
    final eigen = <String, Object?>{};
    for (var i = 0; i + 1 < labels.length; i += 2) {
      if (labels[i] < sleutels.length && labels[i + 1] < waarden.length) {
        eigen[sleutels[labels[i]]] = waarden[labels[i + 1]];
      }
    }
    // Opdracht MoveTo (1) met een aantal, dan paren zigzag-getallen.
    final opdracht = geometrie[0];
    final aantal = opdracht ~/ 8;
    var px = 0, py = 0;
    for (var i = 0; i < aantal && 2 + 2 * i < geometrie.length; i++) {
      px += _zigzag(geometrie[1 + 2 * i]);
      py += _zigzag(geometrie[2 + 2 * i]);
      final lon = (x + px / omvang) / n * 360 - 180;
      final mercator = pi * (1 - 2 * (y + py / omvang) / n);
      final lat = atan((exp(mercator) - exp(-mercator)) / 2) * 180 / pi;
      uit.add((punt: LatLng(lat, lon), eigenschappen: eigen));
    }
  }
}

int _zigzag(int n) => n.isOdd ? -(n + 1) ~/ 2 : n ~/ 2;

Object? _waarde(_Lezer l) {
  Object? waarde;
  while (!l.klaar) {
    final (veld, soort) = l.sleutel();
    switch ((veld, soort)) {
      case (1, 2):
        waarde = l.tekst();
      case (2, 5):
        waarde = l.float32();
      case (3, 1):
        waarde = l.float64();
      case (4, 0) || (5, 0):
        waarde = l.varint();
      case (6, 0):
        waarde = _zigzag(l.varint());
      case (7, 0):
        waarde = l.varint() != 0;
      default:
        l.overslaan(soort);
    }
  }
  return waarde;
}

/// Protobuf lezen, net genoeg voor vectortegels.
class _Lezer {
  _Lezer(this.data, [this.pos = 0, int? eind]) : eind = eind ?? data.length;

  final Uint8List data;
  int pos;
  final int eind;

  bool get klaar => pos >= eind;

  int varint() {
    var waarde = 0, factor = 1;
    while (true) {
      final byte = data[pos++];
      waarde += (byte & 0x7f) * factor;
      if (byte < 0x80) return waarde;
      factor *= 128;
    }
  }

  (int, int) sleutel() {
    final s = varint();
    return (s ~/ 8, s % 8);
  }

  _Lezer stuk() {
    final lengte = varint();
    final kind = _Lezer(data, pos, pos + lengte);
    pos += lengte;
    return kind;
  }

  String tekst() {
    final s = stuk();
    return utf8.decode(
      Uint8List.sublistView(data, s.pos, s.eind),
      allowMalformed: true,
    );
  }

  List<int> ingepakt() {
    final s = stuk();
    final uit = <int>[];
    while (!s.klaar) {
      uit.add(s.varint());
    }
    return uit;
  }

  double float32() {
    final waarde = ByteData.sublistView(
      data,
      pos,
      pos + 4,
    ).getFloat32(0, Endian.little);
    pos += 4;
    return waarde;
  }

  double float64() {
    final waarde = ByteData.sublistView(
      data,
      pos,
      pos + 8,
    ).getFloat64(0, Endian.little);
    pos += 8;
    return waarde;
  }

  void overslaan(int soort) {
    switch (soort) {
      case 0:
        varint();
      case 1:
        pos += 8;
      case 2:
        pos += varint();
      case 5:
        pos += 4;
      default:
        throw FormatException('onbekend protobuf-type $soort');
    }
  }
}
