import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Spreekt de instructies uit. Een los stuk zodat tests en de simulatie een
/// stille stem kunnen geven.
abstract class Stem {
  Future<void> begin(String taal);

  /// Zinnen komen achter elkaar, nooit door elkaar heen.
  void zeg(String zin);
  Future<void> stop();
}

class TtsStem implements Stem {
  final _tts = FlutterTts();
  var _wachtrij = Future<void>.value();

  static final _android =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> begin(String taal) async {
    await _tts.setLanguage(taal);
    // speak() wacht dan tot de zin uit is: de wachtrij hieronder rekent erop.
    await _tts.awaitSpeakCompletion(true);
    // Als navigatiegeluid, zodat het ook met het scherm uit klinkt.
    if (_android) await _tts.setAudioAttributesForNavigation();
  }

  @override
  void zeg(String zin) {
    _wachtrij = _wachtrij
        // focus: muziek gaat op Android zachter zolang de zin duurt.
        .then((_) => _tts.speak(zin, focus: _android))
        .catchError((Object _) {});
  }

  @override
  Future<void> stop() async {
    _wachtrij = Future<void>.value();
    await _tts.stop();
  }
}

final stemProvider = Provider<Stem>((ref) => TtsStem());
