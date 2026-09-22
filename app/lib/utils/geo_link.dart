import 'package:maplibre_gl/maplibre_gl.dart';

/// Wat een andere app met een link vraagt: een plek tonen of er meteen heen.
class GeoVerzoek {
  const GeoVerzoek({this.punt, this.label, this.zoek, this.navigeer = false});

  /// Een punt; [label] is de naam die de andere app erbij gaf.
  final LatLng? punt;
  final String? label;

  /// Of een adres of naam om op te zoeken.
  final String? zoek;

  /// `google.navigation:`: niet alleen tonen, maar een route vanaf hier.
  final bool navigeer;
}

final _getallen = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)');
final _labelNaPunt = RegExp(r'\(([^)]*)\)\s*$');

LatLng? _punt(String tekst) {
  final m = _getallen.firstMatch(tekst);
  if (m == null) return null;
  final lat = double.parse(m[1]!), lon = double.parse(m[2]!);
  if (lat.abs() > 90 || lon.abs() > 180 || (lat == 0 && lon == 0)) return null;
  return LatLng(lat, lon);
}

/// `geo:` (RFC 5870 en Androids uitbreiding met `?q=`) en
/// `google.navigation:q=...`; null als de link er geen van is of niets bruikbaars
/// bevat. Voorbeelden:
///
/// * `geo:52.1,5.2` en `geo:52.1,5.2?z=15`
/// * `geo:0,0?q=52.1,5.2(Bakker Jansen)`
/// * `geo:0,0?q=Stationsplein 1, Utrecht`
/// * `google.navigation:q=52.1,5.2` en `google.navigation:q=Utrecht+Centraal`
GeoVerzoek? leesGeoLink(Uri uri) {
  final schema = uri.scheme.toLowerCase();
  if (schema != 'geo' && schema != 'google.navigation') return null;
  // Uri parseert "geo:52.1,5.2?q=..." zonder host; pad en query los.
  final ruw = uri.toString().substring(schema.length + 1);
  final vraagteken = ruw.indexOf('?');
  final pad = vraagteken < 0 ? ruw : ruw.substring(0, vraagteken);
  final query = vraagteken < 0 ? '' : ruw.substring(vraagteken + 1);
  String? q;
  for (final deel in query.split('&')) {
    final teken = deel.indexOf('=');
    if (teken > 0 && deel.substring(0, teken) == 'q') {
      q = Uri.decodeQueryComponent(deel.substring(teken + 1)).trim();
    }
  }
  final navigeer = schema == 'google.navigation';
  if (navigeer) {
    // google.navigation:q=... staat in het "pad".
    if (pad.startsWith('q=')) {
      q = Uri.decodeQueryComponent(pad.substring(2)).trim();
    }
  }
  if (q != null && q.isNotEmpty) {
    final punt = _punt(q);
    if (punt != null) {
      final label = _labelNaPunt.firstMatch(q)?[1]?.trim();
      return GeoVerzoek(
        punt: punt,
        label: label == null || label.isEmpty ? null : label,
        navigeer: navigeer,
      );
    }
    return GeoVerzoek(zoek: q, navigeer: navigeer);
  }
  final punt = _punt(Uri.decodeComponent(pad));
  return punt == null ? null : GeoVerzoek(punt: punt, navigeer: navigeer);
}
