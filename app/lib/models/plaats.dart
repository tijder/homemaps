import 'package:maplibre_gl/maplibre_gl.dart';

/// Een zoekresultaat van Photon, of een punt dat op de kaart is aangewezen.
class Plaats {
  const Plaats({
    required this.naam,
    required this.punt,
    this.omschrijving = '',
  });

  final String naam;
  final String omschrijving;
  final LatLng punt;

  /// Een los punt zonder adres: de coördinaten zijn dan de naam.
  factory Plaats.vanPunt(LatLng punt) => Plaats(
    naam:
        '${punt.latitude.toStringAsFixed(5)}, ${punt.longitude.toStringAsFixed(5)}',
    punt: punt,
  );

  /// Eén GeoJSON-feature uit het antwoord van Photon.
  factory Plaats.vanPhoton(Map<String, dynamic> feature) {
    final p = (feature['properties'] as Map?)?.cast<String, dynamic>() ?? {};
    final c = (feature['geometry']['coordinates'] as List).cast<num>();
    String? tekst(String sleutel) {
      final waarde = p[sleutel];
      return waarde is String && waarde.isNotEmpty ? waarde : null;
    }

    final straat = tekst('street');
    final nummer = tekst('housenumber');
    final adres = straat == null
        ? null
        : (nummer == null ? straat : '$straat $nummer');
    // Photon laat `name` weg zodra er een huisnummer bij zit; dan is het adres
    // de naam.
    final naam =
        tekst('name') ??
        adres ??
        tekst('city') ??
        tekst('county') ??
        tekst('state') ??
        tekst('country') ??
        '';
    final delen = <String>[
      if (adres != null && adres != naam) adres,
      ?tekst('postcode'),
      if (tekst('city') != naam) ?tekst('city'),
      if (tekst('country') != naam) ?tekst('country'),
    ];
    return Plaats(
      naam: naam,
      omschrijving: delen.join(', '),
      punt: LatLng(c[1].toDouble(), c[0].toDouble()),
    );
  }
}
