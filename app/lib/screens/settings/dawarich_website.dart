import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../services/dawarich_service.dart';

/// Signing in on the Dawarich website, inside the app, like the official
/// Dawarich apps: that way OIDC works too (Keycloak, Authentik, …).
/// With `?client=android` or `?client=ios` Dawarich redirects after signing in
/// to `/auth/ios/success?token=…`; we intercept that and the page closes with
/// the API key. Android and iOS only: there's no WebView on the web.
class DawarichWebsiteLogin extends StatefulWidget {
  const DawarichWebsiteLogin({super.key, required this.server});

  final String server;

  /// Opens the page; the API key, or null if the user went back.
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
  int _progress = 0;
  String? _error;
  bool _done = false;

  static final _client = defaultTargetPlatform == TargetPlatform.iOS
      ? 'ios'
      : 'android';

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => _inspect(request.url)
              ? NavigationDecision.prevent
              : NavigationDecision.navigate,
          // A redirect from the server doesn't always come by as a request;
          // the address does change though.
          onUrlChange: (urlChange) {
            if (urlChange.url case final url?) _inspect(url);
          },
          onPageStarted: _inspect,
          onProgress: (percent) {
            if (mounted) setState(() => _progress = percent);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              if (mounted) setState(() => _error = error.description);
            }
          },
        ),
      )
      ..loadRequest(
        Uri.parse('${widget.server}/users/sign_in?client=$_client'),
        headers: {'X-Dawarich-Client': _client},
      );
  }

  /// Is this the redirect with the token? Then we're done.
  bool _inspect(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !DawarichService.isHandoff(uri)) return false;
    final key = DawarichService.keyFromHandoff(uri);
    if (!_done && mounted) {
      _done = true;
      // Empty: the redirect, but no key in it.
      Navigator.of(context).pop(key ?? '');
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.dawarichWebsiteTitle),
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
        actions: [
          IconButton(
            tooltip: l.tryAgain,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _error = null);
              _web.reload();
            },
          ),
        ],
      ),
      body: _error == null
          ? WebViewWidget(controller: _web)
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l.dawarichWebsiteError(_error!),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
    );
  }
}
