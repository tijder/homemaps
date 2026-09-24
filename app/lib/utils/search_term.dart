import 'package:maplibre_gl/maplibre_gl.dart';

/// A Dutch postcode with house number: "1273 CV 20", "1273CV 20",
/// "1273cv,20", "1273CV20". Free-text search in Photon only returns the
/// postcode; its structured endpoint can handle the combination.
final _postcodeHouseNumber = RegExp(
  r'^(\d{4})\s*([A-Za-z]{2})[\s,]*(\d+[\w-]*)$',
);

({String postcode, String houseNumber})? parsePostcodeHouseNumber(String text) {
  final match = _postcodeHouseNumber.firstMatch(text.trim());
  if (match == null) return null;
  return (
    postcode: '${match[1]} ${match[2]!.toUpperCase()}',
    houseNumber: match[3]!,
  );
}

/// "52.09, 5.12" or "52.09 5.12". Both halves must be fully numeric:
/// otherwise "1273CV 20" is read as a coordinate.
final _coordinate = RegExp(
  r'^(-?\d{1,2}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)$',
);

LatLng? parseCoordinate(String text) {
  final match = _coordinate.firstMatch(text.trim());
  if (match == null) return null;
  final lat = double.parse(match[1]!);
  final lon = double.parse(match[2]!);
  if (lat.abs() > 90 || lon.abs() > 180) return null;
  return LatLng(lat, lon);
}
