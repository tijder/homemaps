import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'voice.dart';

Voice createVoice() => WebVoice();

/// The browser's speech, directly. Not via flutter_tts: on a speech error (a
/// sentence that gets cut off, or a browser without voices) it passes the JS
/// error code through a method channel -- an uncaught "Invalid argument" --
/// and never completes the sentence being waited on, so every following
/// sentence stays silent.
class WebVoice implements Voice {
  var _language = 'nl-NL';
  var _queue = Future<void>.value();

  @override
  Future<void> begin(String language) async => _language = language;

  @override
  void say(String sentence) {
    _queue = _queue.then((_) => _speak(sentence)).catchError((Object _) {});
  }

  Future<void> _speak(String sentence) {
    final done = Completer<void>();
    void finish(web.Event _) {
      if (!done.isCompleted) done.complete();
    }

    final utterance = web.SpeechSynthesisUtterance(sentence)
      ..lang = _language
      ..onend = finish.toJS
      ..onerror = finish.toJS;
    web.window.speechSynthesis.speak(utterance);
    return done.future.timeout(maxSpeakDuration(sentence), onTimeout: () {});
  }

  @override
  Future<void> stop() async {
    _queue = Future<void>.value();
    web.window.speechSynthesis.cancel();
  }
}
