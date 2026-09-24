import 'package:maplibre_gl/maplibre_gl.dart';

/// What another app asks for with a link: show a place or go there right away.
class GeoRequest {
  const GeoRequest({
    this.point,
    this.label,
    this.search,
    this.navigate = false,
  });

  /// A point; [label] is the name the other app gave with it.
  final LatLng? point;
  final String? label;

  /// Or an address or name to search for.
  final String? search;

  /// `google.navigation:`: not just show, but a route from here.
  final bool navigate;
}

final _numbers = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)');
final _labelAfterPoint = RegExp(r'\(([^)]*)\)\s*$');

LatLng? _point(String text) {
  final m = _numbers.firstMatch(text);
  if (m == null) return null;
  final lat = double.parse(m[1]!), lon = double.parse(m[2]!);
  if (lat.abs() > 90 || lon.abs() > 180 || (lat == 0 && lon == 0)) return null;
  return LatLng(lat, lon);
}

/// `geo:` (RFC 5870 and Android's extension with `?q=`) and
/// `google.navigation:q=...`; null if the link is neither or contains nothing
/// usable. Examples:
///
/// * `geo:52.1,5.2` and `geo:52.1,5.2?z=15`
/// * `geo:0,0?q=52.1,5.2(Bakker Jansen)`
/// * `geo:0,0?q=Stationsplein 1, Utrecht`
/// * `google.navigation:q=52.1,5.2` and `google.navigation:q=Utrecht+Centraal`
GeoRequest? parseGeoLink(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'geo' && scheme != 'google.navigation') return null;
  // Uri parses "geo:52.1,5.2?q=..." without a host; split path and query.
  final raw = uri.toString().substring(scheme.length + 1);
  final questionMark = raw.indexOf('?');
  final path = questionMark < 0 ? raw : raw.substring(0, questionMark);
  final query = questionMark < 0 ? '' : raw.substring(questionMark + 1);
  String? q;
  for (final part in query.split('&')) {
    final eqIndex = part.indexOf('=');
    if (eqIndex > 0 && part.substring(0, eqIndex) == 'q') {
      q = Uri.decodeQueryComponent(part.substring(eqIndex + 1)).trim();
    }
  }
  final navigate = scheme == 'google.navigation';
  if (navigate) {
    // google.navigation:q=... is in the "path".
    if (path.startsWith('q=')) {
      q = Uri.decodeQueryComponent(path.substring(2)).trim();
    }
  }
  if (q != null && q.isNotEmpty) {
    final point = _point(q);
    if (point != null) {
      final label = _labelAfterPoint.firstMatch(q)?[1]?.trim();
      return GeoRequest(
        point: point,
        label: label == null || label.isEmpty ? null : label,
        navigate: navigate,
      );
    }
    return GeoRequest(search: q, navigate: navigate);
  }
  final point = _point(Uri.decodeComponent(path));
  return point == null ? null : GeoRequest(point: point, navigate: navigate);
}
