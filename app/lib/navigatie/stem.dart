import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'stem_stub.dart' if (dart.library.js_interop) 'stem_web.dart';

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
  static final _ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<void> begin(String taal) async {
    await _tts.setLanguage(taal);
    // speak() wacht dan tot de zin uit is: de wachtrij hieronder rekent erop.
    await _tts.awaitSpeakCompletion(true);
    // Als navigatiegeluid, zodat het ook met het scherm uit klinkt.
    if (_android) await _tts.setAudioAttributesForNavigation();
    if (_ios) {
      // Playback klinkt ook met het scherm uit en de stilteschakelaar aan;
      // muziek gaat zachter zolang de zin duurt, een podcast pauzeert.
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.duckOthers,
        IosTextToSpeechAudioCategoryOptions
            .interruptSpokenAudioAndMixWithOthers,
      ], IosTextToSpeechAudioMode.voicePrompt);
    }
  }

  @override
  void zeg(String zin) {
    _wachtrij = _wachtrij
        // focus: muziek gaat op Android zachter zolang de zin duurt.
        .then(
          (_) => _tts
              .speak(zin, focus: _android)
              .timeout(maxSpreekduur(zin), onTimeout: () {}),
        )
        .catchError((Object _) {});
  }

  @override
  Future<void> stop() async {
    _wachtrij = Future<void>.value();
    await _tts.stop();
  }
}

/// Zo lang mag een zin hooguit duren. Wie op het einde van een zin wacht en het
/// nooit hoort (een spraakfout die de plugin inslikt), blokkeert anders elke
/// zin die erna komt. Ruim: spraak haalt zo'n 15 tekens per seconde.
Duration maxSpreekduur(String zin) =>
    Duration(milliseconds: 4000 + zin.length * 120);

/// Op Android en iOS flutter_tts; in de browser de spraak van de browser zelf
/// (zie stem_web.dart).
final stemProvider = Provider<Stem>((ref) => maakStem());
