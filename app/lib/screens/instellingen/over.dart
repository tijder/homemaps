import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import 'sectie.dart';

/// Wat HomeMaps is, welke versie, en waar de kaart, de routes, het zoeken en
/// het verkeer vandaan komen (de naamsvermelding die OpenStreetMap vraagt).
class OverInstellingen extends StatelessWidget {
  const OverInstellingen({super.key});

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
    return FutureBuilder<PackageInfo>(
      future: info(),
      builder: (context, snapshot) {
        final pakket = snapshot.data;
        final versie = pakket == null
            ? null
            : pakket.buildNumber.isEmpty
            ? pakket.version
            : '${pakket.version} (${pakket.buildNumber})';
        return InstellingenLijst(
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
            const SizedBox(height: 24),
            InstellingenSectie(
              titel: l.bronnen,
              children: [
                for (final (wat, naam, url) in bronnen)
                  ListTile(
                    title: Text(naam),
                    subtitle: Text(wat),
                    trailing: const Icon(Icons.open_in_new, size: 20),
                    onTap: () => _open(url),
                  ),
              ],
            ),
            InstellingenSectie(
              children: [
                ListTile(
                  leading: const Icon(Icons.code),
                  title: Text(l.broncode),
                  subtitle: const Text('github.com/tijder/homemaps'),
                  trailing: const Icon(Icons.open_in_new, size: 20),
                  onTap: () => _open(broncode),
                ),
                ListTile(
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
            ),
          ],
        );
      },
    );
  }
}
