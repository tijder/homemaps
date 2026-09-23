import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

/// Wat HomeMaps is, welke versie, en waar de kaart, de routes, het zoeken en
/// het verkeer vandaan komen (de naamsvermelding die OpenStreetMap vraagt).
@RoutePage()
class OverScreen extends StatelessWidget {
  const OverScreen({super.key});

  static const broncode = 'https://github.com/tijder/homemaps';

  /// Zoals [PackageInfo.fromPlatform] het geeft; in tests te vervangen.
  @visibleForTesting
  static Future<PackageInfo> Function() info = PackageInfo.fromPlatform;

  static Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on Object {
      // Geen browser: dan blijft het bij de tekst.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tekst = Theme.of(context).textTheme;
    final bronnen = [
      (
        l.bronKaartgegevens,
        'OpenStreetMap',
        'https://www.openstreetmap.org/copyright',
      ),
      (l.bronTegels, 'OpenMapTiles', 'https://openmaptiles.org'),
      (l.bronRoutes, 'Valhalla', 'https://github.com/valhalla/valhalla'),
      (l.bronZoeken, 'Photon', 'https://github.com/komoot/photon'),
      (l.bronVerkeer, 'NDW open data', 'https://opendata.ndw.nu'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l.overHomeMaps)),
      body: FutureBuilder<PackageInfo>(
        future: info(),
        builder: (context, snapshot) {
          final pakket = snapshot.data;
          final versie = pakket == null
              ? null
              : pakket.buildNumber.isEmpty
              ? pakket.version
              : '${pakket.version} (${pakket.buildNumber})';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 8),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 88,
                    height: 88,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: Text(l.appTitel, style: tekst.headlineSmall)),
              if (versie != null)
                Center(child: Text(l.versie(versie), style: tekst.bodyMedium)),
              const SizedBox(height: 16),
              Text(l.overBeschrijving, textAlign: TextAlign.center),
              const Divider(height: 32),
              Text(l.bronnen, style: tekst.titleMedium),
              for (final (wat, naam, url) in bronnen)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(naam),
                  subtitle: Text(wat),
                  trailing: const Icon(Icons.open_in_new, size: 20),
                  onTap: () => _open(url),
                ),
              const Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.code),
                title: Text(l.broncode),
                subtitle: const Text('github.com/tijder/homemaps'),
                trailing: const Icon(Icons.open_in_new, size: 20),
                onTap: () => _open(broncode),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(l.licenties),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: l.appTitel,
                  applicationVersion: versie,
                  applicationIcon: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.asset(
                      'assets/icon/icon.png',
                      width: 48,
                      height: 48,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
