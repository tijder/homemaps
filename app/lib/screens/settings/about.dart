import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../services/app_log.dart';
import 'section.dart';

/// What HomeMaps is, which version, and where the map, the routes, search and
/// traffic come from (the attribution OpenStreetMap asks for).
class AboutSettings extends StatelessWidget {
  const AboutSettings({super.key});

  static const sourceCode = 'https://github.com/tijder/homemaps';

  /// As [PackageInfo.fromPlatform] returns it; replaceable in tests.
  @visibleForTesting
  static Future<PackageInfo> Function() info = PackageInfo.fromPlatform;

  static Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on Object {
      // No browser: then it's just the text.
    }
  }

  /// The system save dialog; replaceable in tests. Null when cancelled.
  @visibleForTesting
  static Future<Uri?> Function(String fileName, Uint8List bytes) saveFile =
      (fileName, bytes) => FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: 'text/plain',
      );

  static Future<void> _saveLog(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = AppLog.instance.export();
      if (bytes == null) {
        messenger.showSnackBar(SnackBar(content: Text(l.logEmpty)));
        return;
      }
      final date = DateTime.now().toIso8601String().split('T').first;
      if (await saveFile('homemaps-log-$date.txt', bytes) == null) return;
      messenger.showSnackBar(SnackBar(content: Text(l.logSaved)));
    } on Object catch (error) {
      debugPrint('Could not save the log: $error');
      messenger.showSnackBar(
        SnackBar(content: Text(l.logSaveFailed('$error'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final sources = [
      (
        l.sourceMapData,
        'OpenStreetMap',
        'https://www.openstreetmap.org/copyright',
      ),
      (l.sourceTiles, 'OpenMapTiles', 'https://openmaptiles.org'),
      (l.sourceRouting, 'Valhalla', 'https://github.com/valhalla/valhalla'),
      (l.sourceSearch, 'Photon', 'https://github.com/komoot/photon'),
      (l.sourceTraffic, 'NDW open data', 'https://opendata.ndw.nu'),
    ];
    return FutureBuilder<PackageInfo>(
      future: info(),
      builder: (context, snapshot) {
        final packageInfo = snapshot.data;
        final version = packageInfo == null
            ? null
            : packageInfo.buildNumber.isEmpty
            ? packageInfo.version
            : '${packageInfo.version} (${packageInfo.buildNumber})';
        return SettingsList(
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
            Center(child: Text(l.appTitle, style: text.headlineSmall)),
            if (version != null)
              Center(child: Text(l.version(version), style: text.bodyMedium)),
            const SizedBox(height: 16),
            Text(l.aboutDescription, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            SettingsSection(
              title: l.sources,
              children: [
                for (final (what, label, url) in sources)
                  ListTile(
                    title: Text(label),
                    subtitle: Text(what),
                    trailing: const Icon(Icons.open_in_new, size: 20),
                    onTap: () => _open(url),
                  ),
              ],
            ),
            SettingsSection(
              children: [
                ListTile(
                  leading: const Icon(Icons.code),
                  title: Text(l.sourceCode),
                  subtitle: const Text('github.com/tijder/homemaps'),
                  trailing: const Icon(Icons.open_in_new, size: 20),
                  onTap: () => _open(sourceCode),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(l.licenses),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: l.appTitle,
                    applicationVersion: version,
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
                // The web has no log file: the browser console has it all.
                if (!kIsWeb)
                  ListTile(
                    leading: const Icon(Icons.save_alt),
                    title: Text(l.saveLog),
                    subtitle: Text(l.saveLogSubtitle),
                    onTap: () => _saveLog(context),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
