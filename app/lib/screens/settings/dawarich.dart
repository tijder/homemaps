import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/dawarich.dart';
import '../../providers/dawarich.dart';
import '../../providers/location_sharing.dart';
import '../../services/dawarich_service.dart';
import 'dawarich_website.dart';
import 'section.dart';

/// A [DawarichError] as a sentence for the screen.
String dawarichErrorText(AppLocalizations l, Object error) => switch (error) {
  DawarichError(kind: DawarichErrorKind.auth) => l.dawarichErrorCredentials,
  DawarichError(kind: DawarichErrorKind.passwordDisabled) =>
    l.dawarichErrorPasswordDisabled,
  DawarichError(kind: DawarichErrorKind.blocked) => l.dawarichErrorBlocked,
  DawarichError(kind: DawarichErrorKind.noFamily) => l.dawarichNoFamily,
  DawarichError(kind: DawarichErrorKind.noSubscription) =>
    l.dawarichNoSubscription,
  // In the browser a rejected CORS request can't be told apart from
  // "offline"; CORS is then the most likely.
  DawarichError(kind: DawarichErrorKind.connection, :final detail) =>
    kIsWeb ? l.dawarichErrorCors : l.dawarichErrorConnection(detail ?? ''),
  DawarichError(kind: DawarichErrorKind.notDawarich) =>
    l.dawarichErrorNotDawarich,
  DawarichError(:final detail) => l.dawarichErrorUnknown(detail ?? ''),
  _ => l.dawarichErrorUnknown('$error'),
};

/// Dawarich: first the connection (server, then signing in), only after that
/// the settings: family sharing, sharing while navigating and the family on
/// the map.
class DawarichSettings extends ConsumerWidget {
  const DawarichSettings({super.key});

  /// Signing in on the website; replaceable in tests, because there's no
  /// WebView there.
  @visibleForTesting
  static Future<String?> Function(BuildContext context, String server)
  openWebsite = DawarichWebsiteLogin.open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(dawarichProvider);
    return account == null ? const _Connect() : _SignedIn(account);
  }
}

/// An error at the bottom of a step, noticeable but calm.
class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Material(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: colors.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
              ?action,
            ],
          ),
        ),
      ),
    );
  }
}

/// A button with a spinner while it's busy.
class _Button extends StatelessWidget {
  const _Button({required this.text, required this.busy, this.onPressed});

  final String text;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(text),
    ),
  );
}

/// Not signed in: step 1 the server (is there a Dawarich?), step 2 signing in.
class _Connect extends ConsumerStatefulWidget {
  const _Connect();

  @override
  ConsumerState<_Connect> createState() => _ConnectState();
}

class _ConnectState extends ConsumerState<_Connect> {
  late final _server = TextEditingController(
    text: ref.read(dawarichProvider.notifier).previousServer ?? '',
  );
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _key = TextEditingController();

  /// After step 1: the address where Dawarich answered, and its version.
  String? _connected;
  String? _version;
  bool _withKey = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_server, _email, _password, _key]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Something that asks the server, with the spinner and the error around it.
  Future<void> _run(Future<void> Function() work) async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } on DawarichError catch (error) {
      if (mounted) setState(() => _error = dawarichErrorText(l, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final l = AppLocalizations.of(context);
    final server = DawarichService.normalize(_server.text);
    if (server == null) {
      setState(() => _error = l.serverInvalid);
      return;
    }
    await _run(() async {
      final info = await ref.read(dawarichServiceProvider).connect(server);
      if (!mounted) return;
      setState(() {
        _connected = server;
        _version = info.version;
      });
    });
  }

  void _changeServer() => setState(() {
    _connected = null;
    _error = null;
  });

  Future<void> _withPassword() => _run(() async {
    final server = _connected!;
    final notifier = ref.read(dawarichProvider.notifier);
    final outcome = await notifier.signIn(server, _email.text, _password.text);
    if (outcome is DawarichTwoFactor) {
      final code = await _askCode();
      if (code == null || code.trim().isEmpty) return;
      await notifier.confirm(server, outcome.token, code);
    }
  });

  Future<void> _viaWebsite() => _run(() async {
    final server = _connected!;
    final key = await DawarichSettings.openWebsite(context, server);
    // Null: went back without signing in.
    if (key == null) return;
    if (key.isEmpty) {
      throw const DawarichError(DawarichErrorKind.unknown, 'no key');
    }
    await ref.read(dawarichProvider.notifier).withKey(server, key);
  });

  Future<void> _withApiKey() => _run(
    () => ref.read(dawarichProvider.notifier).withKey(_connected!, _key.text),
  );

  Future<String?> _askCode() {
    final code = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l.dawarichCode),
          content: TextField(
            controller: code,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            onSubmitted: (text) => Navigator.pop(context, text),
            decoration: InputDecoration(helperText: l.dawarichCodeHelp),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, code.text),
              child: Text(l.dawarichConfirm),
            ),
          ],
        );
      },
    ).whenComplete(code.dispose);
  }

  static InputDecoration _field(String label, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final error = _error == null ? null : _Notice(_error!);
    final connected = _connected;

    // Step 1: where is your Dawarich?
    if (connected == null) {
      return SettingsList(
        children: [
          SettingsSection(
            title: l.dawarichStepServer,
            help: l.dawarichHelp,
            children: [
              SectionBlock(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _connect(),
                      decoration: _field(
                        l.dawarichServer,
                        hint: 'https://dawarich.example',
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Button(
                      text: l.dawarichConnect,
                      busy: _busy,
                      onPressed: _connect,
                    ),
                  ],
                ),
              ),
            ],
          ),
          ?error,
        ],
      );
    }

    // Step 2: signing in.
    return AutofillGroup(
      child: SettingsList(
        children: [
          SettingsSection(
            title: l.dawarichStepServer,
            children: [
              ListTile(
                leading: Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(Uri.parse(connected).host),
                subtitle: Text(
                  _version == null
                      ? l.dawarichConnected
                      : l.dawarichConnectedVersion(_version!),
                ),
                trailing: TextButton(
                  onPressed: _busy ? null : _changeServer,
                  child: Text(l.dawarichChange),
                ),
              ),
            ],
          ),
          ?error,
          SettingsSection(
            title: l.dawarichStepSignIn,
            children: [
              SectionBlock(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: _field(l.dawarichEmail),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _withPassword(),
                      decoration: _field(l.dawarichPassword),
                    ),
                    const SizedBox(height: 16),
                    _Button(
                      text: l.dawarichSignIn,
                      busy: _busy && !_withKey,
                      onPressed: _withPassword,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SettingsSection(
            title: l.dawarichOtherWays,
            children: [
              if (!kIsWeb)
                ListTile(
                  leading: const Icon(Icons.open_in_browser),
                  title: Text(l.dawarichWebsiteSignIn),
                  subtitle: Text(l.dawarichWebsiteHelp),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !_busy,
                  onTap: _viaWebsite,
                ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(l.dawarichWithKey),
                subtitle: Text(l.dawarichKeyHelp),
                trailing: Icon(
                  _withKey ? Icons.expand_less : Icons.expand_more,
                ),
                onTap: () => setState(() => _withKey = !_withKey),
              ),
              if (_withKey)
                SectionBlock(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _key,
                        obscureText: true,
                        autocorrect: false,
                        onSubmitted: (_) => _withApiKey(),
                        decoration: _field(l.dawarichKey),
                      ),
                      const SizedBox(height: 16),
                      _Button(
                        text: l.dawarichSignIn,
                        busy: _busy,
                        onPressed: _withApiKey,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Signed in: first whether the connection still works; the settings only
/// once it does.
class _SignedIn extends ConsumerWidget {
  const _SignedIn(this.account);

  final DawarichAccount account;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.dawarichSignOutQuestion),
        content: Text(l.dawarichSignOutHelp),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.dawarichSignOut),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await ref.read(dawarichProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final share = ref.watch(shareSettingsProvider);
    final notifier = ref.read(dawarichProvider.notifier);
    final connection = ref.watch(dawarichConnectionProvider);
    final error = connection.error;
    final expired =
        error is DawarichError && error.kind == DawarichErrorKind.auth;
    final host = Uri.parse(account.server).host;
    final (status, statusColor) = switch (connection) {
      _ when expired => (l.dawarichSessionExpired, colors.error),
      AsyncValue(hasError: true) => (l.dawarichUnreachable, colors.error),
      AsyncValue(isLoading: true) => (l.dawarichChecking, null),
      AsyncValue(:final value) => (
        value?.version == null
            ? l.dawarichConnected
            : l.dawarichConnectedVersion(value!.version!),
        null,
      ),
    };

    return SettingsList(
      children: [
        SettingsSection(
          title: l.dawarichAccount,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: Text(
                  account.email.isEmpty
                      ? '?'
                      : account.email.substring(0, 1).toUpperCase(),
                ),
              ),
              title: Text(account.email.isEmpty ? host : account.email),
              subtitle: Text(
                '$host · $status',
                style: TextStyle(color: statusColor),
              ),
              trailing: TextButton(
                onPressed: () => _signOut(context, ref),
                child: Text(l.dawarichSignOut),
              ),
            ),
          ],
        ),
        // The key no longer works: only signing in again, with the server
        // already filled in.
        if (expired)
          _Notice(
            l.dawarichSessionExpiredHelp,
            action: TextButton(
              onPressed: notifier.signOut,
              child: Text(l.dawarichSignInAgain),
            ),
          )
        else ...[
          if (error != null)
            _Notice(
              dawarichErrorText(l, error),
              action: TextButton(
                onPressed: () => ref.invalidate(dawarichConnectionProvider),
                child: Text(l.tryAgain),
              ),
            ),
          if (connection.isLoading && !connection.hasValue)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            )
          else ...[
            SettingsSection(
              title: l.dawarichFamily,
              children: [
                _FamilySharing(account),
                SwitchListTile(
                  secondary: const Icon(Icons.groups_outlined),
                  title: Text(l.dawarichShowFamily),
                  subtitle: Text(l.dawarichShowFamilyHelp),
                  value: account.showFamily,
                  onChanged: account.family ? notifier.setShowFamily : null,
                ),
              ],
            ),
            SettingsSection(
              title: l.dawarichNavigation,
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.share_location),
                  title: Text(l.dawarichShareEnRoute),
                  subtitle: Text(l.dawarichShareEnRouteHelp),
                  value: share.enabled && sharesViaDawarich(share, account),
                  onChanged: notifier.setShareEnRoute,
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

/// The switch to share your location with the family, or why that isn't
/// possible.
class _FamilySharing extends ConsumerWidget {
  const _FamilySharing(this.account);

  final DawarichAccount account;

  Future<ShareDuration?> _chooseDuration(BuildContext context) =>
      showModalBottomSheet<ShareDuration>(
        context: context,
        builder: (context) {
          final l = AppLocalizations.of(context);
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    l.dawarichHowLong,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final duration in ShareDuration.values)
                  ListTile(
                    title: Text(l.dawarichDuration(duration.name)),
                    onTap: () => Navigator.pop(context, duration),
                  ),
              ],
            ),
          );
        },
      );

  Future<void> _apply(BuildContext context, WidgetRef ref, bool enabled) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    ShareDuration? duration;
    if (enabled) {
      duration = await _chooseDuration(context);
      if (duration == null) return;
    }
    try {
      await ref
          .read(familyProvider.notifier)
          .setSharing(enabled, duration: duration);
    } on DawarichError catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(dawarichErrorText(l, error))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (!account.family) {
      return ListTile(
        leading: const Icon(Icons.family_restroom),
        title: Text(l.dawarichNoSubscription),
      );
    }
    final family = ref.watch(familyProvider);
    if (family.value case final status?) {
      final until = status.expiresAt;
      final sharing = status.isSharing(DateTime.now());
      return SwitchListTile(
        secondary: const Icon(Icons.family_restroom),
        title: Text(l.dawarichShareWithFamily),
        subtitle: Text(
          !sharing
              ? l.dawarichNotSharing
              : until == null
              ? l.dawarichSharingAlways
              : l.dawarichSharingUntil(_time(l, until)),
        ),
        value: sharing,
        onChanged: family.isLoading
            ? null
            : (enabled) => _apply(context, ref, enabled),
      );
    }
    if (family.error case final error?) {
      final noFamily =
          error is DawarichError && error.kind == DawarichErrorKind.noFamily;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dawarichErrorText(l, error)),
            Align(
              alignment: Alignment.centerLeft,
              child: noFamily
                  ? TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse('${account.server}/family'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text(l.dawarichOpenWebsite),
                    )
                  : TextButton(
                      onPressed: () => ref.invalidate(familyProvider),
                      child: Text(l.tryAgain),
                    ),
            ),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: LinearProgressIndicator(),
    );
  }

  /// Today just the time, otherwise the day too.
  static String _time(AppLocalizations l, DateTime time) {
    final now = DateTime.now();
    final today =
        time.year == now.year && time.month == now.month && time.day == now.day;
    return today
        ? DateFormat.Hm(l.localeName).format(time)
        : DateFormat.MMMd(l.localeName).add_Hm().format(time);
  }
}
