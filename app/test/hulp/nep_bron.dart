import 'dart:async';

import 'package:homemaps/providers/locatie.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Een locatiebron zonder GPS: de test bepaalt de toestemming en de fixes.
class NepBron implements LocatieBron {
  NepBron(this.antwoord);

  Toestemming antwoord;
  int gevraagd = 0;
  final fixes = StreamController<LocatieFix>.broadcast();
  bool? laatsteNauwkeurig;
  ({String titel, String tekst})? laatsteMelding;

  @override
  Future<Toestemming> controleer() async =>
      antwoord == Toestemming.ja ? Toestemming.ja : Toestemming.nee;

  @override
  Future<Toestemming> vraag() async {
    gevraagd++;
    return antwoord;
  }

  @override
  Stream<LocatieFix> volg({
    required bool nauwkeurig,
    ({String titel, String tekst})? melding,
  }) {
    laatsteNauwkeurig = nauwkeurig;
    laatsteMelding = melding;
    return fixes.stream;
  }
}

LocatieFix fix(double lat) =>
    LocatieFix(punt: LatLng(lat, 5.0), tijd: DateTime(2026, 9, 22));
