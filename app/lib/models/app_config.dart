/// Waar de app zijn backends vindt. Alles hangt onder één server: `/valhalla`,
/// `/geocode`, `/tiles` en `/verkeer` (zo levert de chart het).
class AppConfig {
  const AppConfig({
    required this.valhallaUrl,
    required this.geocodeUrl,
    required this.tilesUrl,
    required this.verkeerUrl,
    required this.verkeerGeplandUrl,
  });

  final String valhallaUrl;
  final String geocodeUrl;
  final String tilesUrl;

  /// De verkeerslaag (GeoJSON) die de importer elke ronde maakt.
  final String verkeerUrl;

  /// Geplande afsluitingen van de komende week, voor "later vertrekken".
  final String verkeerGeplandUrl;

  /// [overschrijf] is de inhoud van `/config.json` (web) en mag elk ervan
  /// vervangen, bijvoorbeeld als de tegels op een eigen hostnaam staan.
  factory AppConfig.vanServer(
    String server, [
    Map<String, dynamic> overschrijf = const {},
  ]) {
    final basis = server.endsWith('/')
        ? server.substring(0, server.length - 1)
        : server;
    String kies(String sleutel, String pad) {
      final waarde = overschrijf[sleutel];
      return waarde is String && waarde.isNotEmpty ? waarde : '$basis$pad';
    }

    return AppConfig(
      valhallaUrl: kies('valhallaUrl', '/valhalla'),
      geocodeUrl: kies('geocodeUrl', '/geocode'),
      tilesUrl: kies('tilesUrl', '/tiles'),
      verkeerUrl: kies('verkeerUrl', '/verkeer'),
      verkeerGeplandUrl: kies('verkeerGeplandUrl', '/verkeer-gepland'),
    );
  }

  String stijlUrl(String stijl) => '$tilesUrl/styles/$stijl/style.json';
}
