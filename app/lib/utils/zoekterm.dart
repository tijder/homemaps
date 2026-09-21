import 'package:maplibre_gl/maplibre_gl.dart';

/// Een Nederlandse postcode met huisnummer: "1273 CV 20", "1273CV 20",
/// "1273cv,20", "1273CV20". Vrij zoeken levert bij Photon alleen de postcode op;
/// zijn structured-endpoint kan de combinatie wel.
final _postcodeHuisnummer = RegExp(
  r'^(\d{4})\s*([A-Za-z]{2})[\s,]*(\d+[\w-]*)$',
);

({String postcode, String huisnummer})? leesPostcodeHuisnummer(String tekst) {
  final treffer = _postcodeHuisnummer.firstMatch(tekst.trim());
  if (treffer == null) return null;
  return (
    postcode: '${treffer[1]} ${treffer[2]!.toUpperCase()}',
    huisnummer: treffer[3]!,
  );
}

/// "52.09, 5.12" of "52.09 5.12". Beide helften moeten volledig numeriek zijn:
/// anders wordt "1273CV 20" als coördinaat gelezen.
final _coordinaat = RegExp(
  r'^(-?\d{1,2}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)$',
);

LatLng? leesCoordinaat(String tekst) {
  final treffer = _coordinaat.firstMatch(tekst.trim());
  if (treffer == null) return null;
  final lat = double.parse(treffer[1]!);
  final lon = double.parse(treffer[2]!);
  if (lat.abs() > 90 || lon.abs() > 180) return null;
  return LatLng(lat, lon);
}
