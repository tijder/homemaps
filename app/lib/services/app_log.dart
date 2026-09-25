import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// A rolling copy on disk of everything the app logs ([debugPrint] and
/// uncaught errors), so a problem can still be looked into on the next run:
/// About → "Save log" exports it.
///
/// Before [install] — and forever under `flutter test`, where path_provider
/// never answers — the lines stay in a bounded buffer in memory.
class AppLog {
  AppLog({
    this.rootOverride,
    this.maxFileBytes = 1024 * 1024,
    this.maxExportBytes = 2 * 1024 * 1024,
  });

  static final instance = AppLog();

  static const _maxBuffered = 200;

  /// Where the files go instead of the app support directory; for tests.
  final Directory? rootOverride;

  /// Past this the current file becomes the old one (`homemaps.log.1`).
  final int maxFileBytes;

  /// At most this much is exported (old + current file); the end wins.
  final int maxExportBytes;

  final List<String> _buffer = [];
  Directory? _dir;
  File? _file;
  int _size = 0;
  Future<void>? _installing;

  /// Tees [debugPrint] and the uncaught errors into the log and opens the
  /// file. Fire-and-forget from main; nothing on the web. Never throws:
  /// logging must not take the app down, so on failure it stays in memory.
  Future<void> install() {
    if (kIsWeb) return Future.value();
    return _installing ??= () async {
      final print = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) add(message);
        print(message, wrapWidth: wrapWidth);
      };
      // Chain, don't replace: Flutter's own handlers keep showing the errors.
      final flutterError = FlutterError.onError ?? FlutterError.presentError;
      FlutterError.onError = (details) {
        add(
          'Uncaught Flutter error: ${details.exceptionAsString()}\n'
          '${details.stack ?? ''}',
        );
        flutterError(details);
      };
      final platformError = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (error, stack) {
        add('Uncaught error: $error\n$stack');
        return platformError?.call(error, stack) ?? false;
      };
      try {
        final root =
            rootOverride ??
            Directory('${(await getApplicationSupportDirectory()).path}/logs');
        await root.create(recursive: true);
        var version = 'unknown';
        try {
          final info = await PackageInfo.fromPlatform();
          version = '${info.version}+${info.buildNumber}';
        } on Object {
          // No platform channel: keep the placeholder.
        }
        attach(
          root,
          '==== HomeMaps ${DateTime.now().toIso8601String()} '
          '| $version | ${defaultTargetPlatform.name} ====',
        );
      } on Object {
        // Stays in memory.
      }
    }();
  }

  /// One entry, with the time in front.
  void add(String message) {
    final line = '${DateTime.now().toIso8601String()} $message';
    if (_dir == null) {
      _buffer.add(line);
      if (_buffer.length > _maxBuffered) _buffer.removeAt(0);
      return;
    }
    _write('$line\n');
  }

  /// From now on to `homemaps.log` in [dir], starting with [header] and what
  /// was logged so far.
  @visibleForTesting
  void attach(Directory dir, String header) {
    _dir = dir;
    final file = File('${dir.path}/homemaps.log');
    _file = file;
    try {
      _size = file.existsSync() ? file.lengthSync() : 0;
    } on Object {
      _size = 0;
    }
    final pending = [..._buffer];
    _buffer.clear();
    _write('${[header, ...pending].join('\n')}\n');
  }

  void _write(String chunk) {
    if (_file == null) return;
    try {
      if (_size > maxFileBytes) _rotate();
      _file!.writeAsStringSync(chunk, mode: FileMode.append);
      _size += chunk.length;
    } on Object {
      // A full disk is no reason to crash.
    }
  }

  void _rotate() {
    final dir = _dir!;
    try {
      final old = File('${dir.path}/homemaps.log.1');
      if (old.existsSync()) old.deleteSync();
      _file!.renameSync(old.path);
    } on Object {
      // Then the current file just grows.
    }
    _file = File('${dir.path}/homemaps.log');
    _size = 0;
  }

  /// What "Save log" saves: the old file, the current one and what is still
  /// in memory, at most [maxExportBytes]. Null when there is nothing yet.
  Uint8List? export() {
    final parts = <String>[];
    final dir = _dir;
    if (dir != null) {
      for (final name in ['homemaps.log.1', 'homemaps.log']) {
        try {
          final file = File('${dir.path}/$name');
          if (file.existsSync()) parts.add(file.readAsStringSync());
        } on Object {
          // Skip what can't be read.
        }
      }
    }
    if (_buffer.isNotEmpty) parts.add('${_buffer.join('\n')}\n');
    final text = parts.join();
    if (text.isEmpty) return null;
    final bytes = utf8.encode(text);
    return bytes.length > maxExportBytes
        ? Uint8List.sublistView(bytes, bytes.length - maxExportBytes)
        : bytes;
  }
}
