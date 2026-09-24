/// Where the app finds its backends. Everything hangs off one server:
/// `/valhalla`, `/geocode`, `/tiles` and `/traffic` (that's how the chart
/// serves it).
class AppConfig {
  const AppConfig({
    required this.valhallaUrl,
    required this.geocodeUrl,
    required this.tilesUrl,
    required this.trafficUrl,
    required this.trafficPlannedUrl,
    required this.conditionalSpeedsUrl,
  });

  final String valhallaUrl;
  final String geocodeUrl;
  final String tilesUrl;

  /// The traffic layer (GeoJSON) the importer builds every cycle.
  final String trafficUrl;

  /// Planned closures for the coming week, for "depart later".
  final String trafficPlannedUrl;

  /// Speed limits by time of day, per OSM way.
  final String conditionalSpeedsUrl;

  /// [overrides] is the content of `/config.json` (web) and may replace any of
  /// them, for example when the tiles live on their own host name.
  factory AppConfig.fromServer(
    String server, [
    Map<String, dynamic> overrides = const {},
  ]) {
    final base = server.endsWith('/')
        ? server.substring(0, server.length - 1)
        : server;
    String choose(String key, String path) {
      final value = overrides[key];
      return value is String && value.isNotEmpty ? value : '$base$path';
    }

    return AppConfig(
      valhallaUrl: choose('valhallaUrl', '/valhalla'),
      geocodeUrl: choose('geocodeUrl', '/geocode'),
      tilesUrl: choose('tilesUrl', '/tiles'),
      trafficUrl: choose('trafficUrl', '/traffic'),
      trafficPlannedUrl: choose('trafficPlannedUrl', '/traffic-planned'),
      conditionalSpeedsUrl: choose(
        'conditionalSpeedsUrl',
        '/conditional-speeds',
      ),
    );
  }

  String styleUrl(String style) => '$tilesUrl/styles/$style/style.json';
}
