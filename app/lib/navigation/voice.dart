import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'voice_stub.dart' if (dart.library.js_interop) 'voice_web.dart';

/// Speaks the instructions. A separate piece so tests and the simulation can
/// supply a silent voice.
abstract class Voice {
  Future<void> begin(String language);

  /// Sentences come one after another, never over each other.
  void say(String sentence);
  Future<void> stop();
}

class TtsVoice implements Voice {
  final _tts = FlutterTts();
  var _queue = Future<void>.value();

  static final _android =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static final _ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<void> begin(String language) async {
    await _tts.setLanguage(language);
    // speak() then waits until the sentence is done: the queue below relies on it.
    await _tts.awaitSpeakCompletion(true);
    // As navigation audio, so it also plays with the screen off.
    if (_android) await _tts.setAudioAttributesForNavigation();
    if (_ios) {
      // Playback also plays with the screen off and the silent switch on;
      // music is ducked while the sentence lasts, a podcast pauses.
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.duckOthers,
        IosTextToSpeechAudioCategoryOptions
            .interruptSpokenAudioAndMixWithOthers,
      ], IosTextToSpeechAudioMode.voicePrompt);
    }
  }

  @override
  void say(String sentence) {
    _queue = _queue
        // focus: on Android music is ducked while the sentence lasts.
        .then(
          (_) => _tts
              .speak(sentence, focus: _android)
              .timeout(maxSpeakDuration(sentence), onTimeout: () {}),
        )
        .catchError((Object _) {});
  }

  @override
  Future<void> stop() async {
    _queue = Future<void>.value();
    await _tts.stop();
  }
}

/// The longest a sentence may take. Waiting for the end of a sentence and never
/// hearing it (a speech error the plugin swallows) would otherwise block every
/// sentence after it. Generous: speech does about 15 characters per second.
Duration maxSpeakDuration(String sentence) =>
    Duration(milliseconds: 4000 + sentence.length * 120);

/// On Android and iOS flutter_tts; in the browser the browser's own speech
/// (see voice_web.dart).
final voiceProvider = Provider<Voice>((ref) => createVoice());
