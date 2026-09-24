import 'package:maplibre_gl/maplibre_gl.dart';

import '../l10n/app_localizations.dart';

/// A search result from Photon, or a point picked on the map.
class Place {
  const Place({
    required this.label,
    required this.point,
    this.description = '',
    this.myLocation = false,
  });

  final String label;
  final String description;
  final LatLng point;

  /// Your own position at the moment of picking. The name then comes from the
  /// translation (see [display]); navigation uses the live position en route
  /// anyway.
  final bool myLocation;

  factory Place.here(LatLng point) =>
      Place(label: '', point: point, myLocation: true);

  String display(AppLocalizations l) => myLocation ? l.myLocation : label;

  /// A bare point without an address: the coordinates are the name.
  factory Place.fromPoint(LatLng point) => Place(
    label:
        '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
    point: point,
  );

  /// One GeoJSON feature from Photon's response.
  factory Place.fromPhoton(Map<String, dynamic> feature) {
    final p = (feature['properties'] as Map?)?.cast<String, dynamic>() ?? {};
    final c = (feature['geometry']['coordinates'] as List).cast<num>();
    String? text(String key) {
      final value = p[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    final street = text('street');
    final number = text('housenumber');
    final address = street == null
        ? null
        : (number == null ? street : '$street $number');
    // Photon omits `name` as soon as there's a house number; then the address
    // is the name.
    final label =
        text('name') ??
        address ??
        text('city') ??
        text('county') ??
        text('state') ??
        text('country') ??
        '';
    final details = <String>[
      if (address != null && address != label) address,
      ?text('postcode'),
      if (text('city') != label) ?text('city'),
      if (text('country') != label) ?text('country'),
    ];
    return Place(
      label: label,
      description: details.join(', '),
      point: LatLng(c[1].toDouble(), c[0].toDouble()),
    );
  }
}
