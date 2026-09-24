import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../services/dawarich_service.dart';

/// Inloggen op de website van Dawarich, in de app, zoals de officiële
/// Android-app van Dawarich: zo werkt ook OIDC (Keycloak, Authentik, …).
/// Met `?client=android` stuurt Dawarich na het inloggen door naar
/// `/auth/ios/success?token=…`; dat vangen we af en de pagina sluit met de
/// API-sleutel. Alleen Android: op het web is er geen WebView.
class DawarichWebsiteLogin extends StatefulWidget {
  const DawarichWebsiteLogin({super.key, required this.server});

  final String server;

  /// Opent de pagina; de API-sleutel, of null als de gebruiker terugging.
  static Future<String?> open(BuildContext context, String server) =>
      Navigator.of(context).push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => DawarichWebsiteLogin(server: server),
        ),
      );

  @override
  State<DawarichWebsiteLogin> createState() => _DawarichWebsiteLoginState();
}

class _DawarichWebsiteLoginState extends State<DawarichWebsiteLogin> {
  late final WebViewController _web;
  int _voortgang = 0;
  String? _fout;
  bool _klaar = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (verzoek) => _bekijk(verzoek.url)
              ? NavigationDecision.prevent
              : NavigationDecision.navigate,
          // Een doorverwijzing van de server komt niet altijd als verzoek
          // langs; het adres verandert dan wel.
          onUrlChange: (wijziging) {
            if (wijziging.url case final url?) _bekijk(url);
          },
          onPageStarted: _bekijk,
          onProgress: (procent) {
            if (mounted) setState(() => _voortgang = procent);
          },
          onWebResourceError: (fout) {
            if (fout.isForMainFrame ?? true) {
              if (mounted) setState(() => _fout = fout.description);
            }
          },
        ),
      )
      ..loadRequest(
        Uri.parse('${widget.server}/users/sign_in?client=android'),
        headers: const {'X-Dawarich-Client': 'android'},
      );
  }

  /// Is dit de doorverwijzing met de token? Dan klaar.
  bool _bekijk(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !DawarichService.isHandoff(uri)) return false;
    final sleutel = DawarichService.sleutelUitHandoff(uri);
    if (!_klaar && mounted) {
      _klaar = true;
      // Leeg: wel de doorverwijzing, maar geen sleutel erin.
      Navigator.of(context).pop(sleutel ?? '');
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.dawarichWebsiteTitel),
        bottom: _voortgang < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _voortgang / 100),
              )
            : null,
        actions: [
          IconButton(
            tooltip: l.opnieuwProberen,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _fout = null);
              _web.reload();
            },
          ),
        ],
      ),
      body: _fout == null
          ? WebViewWidget(controller: _web)
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l.dawarichWebsiteFout(_fout!),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
    );
  }
}
