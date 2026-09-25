import 'package:dio/dio.dart';

import '../models/app_config.dart';

/// The backends of a HomeMaps server, as the server settings check them.
enum ServerPart { map, search, routes }

/// Which parts of a server answered.
class ServerCheck {
  const ServerCheck(this.working);

  final Set<ServerPart> working;

  bool get works => working.length == ServerPart.values.length;

  /// Nothing answered: probably a typo, or no HomeMaps there.
  bool get unreachable => working.isEmpty;

  Set<ServerPart> get failing => {
    for (final part in ServerPart.values)
      if (!working.contains(part)) part,
  };
}

/// What was typed as a server address, as the app will use it: `https://` in
/// front if there is no scheme. Null if it can't be one.
String? normalizeServer(String text) {
  var address = text.trim();
  if (address.isEmpty) return null;
  if (!address.contains('://')) address = 'https://$address';
  final uri = Uri.tryParse(address);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return address;
}

/// Asks the map, search and routing of [server] one small thing each, at
/// the same time, the way the app uses them.
Future<ServerCheck> checkServer(
  Dio dio,
  String server, {
  CancelToken? cancel,
}) async {
  final config = AppConfig.fromServer(server);
  final options = Options(
    sendTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  );
  Future<ServerPart?> ask(ServerPart part, Uri uri) async {
    try {
      final response = await dio
          .getUri<Object>(uri, options: options, cancelToken: cancel)
          .timeout(const Duration(seconds: 8));
      // A web server that isn't HomeMaps may well answer 200 with a page.
      return response.data is Map ? part : null;
    } on Object {
      return null;
    }
  }

  final answers = await Future.wait([
    ask(ServerPart.map, Uri.parse('${config.tilesUrl}/data/v3.json')),
    ask(
      ServerPart.search,
      Uri.parse(config.geocodeUrl)
          .replace(queryParameters: {'q': 'utrecht', 'limit': '1'}),
    ),
    ask(ServerPart.routes, Uri.parse('${config.valhallaUrl}/status')),
  ]);
  return ServerCheck({...answers.nonNulls});
}
