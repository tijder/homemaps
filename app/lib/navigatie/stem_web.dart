import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'stem.dart';

Stem maakStem() => WebStem();

/// De spraak van de browser, rechtstreeks. Niet via flutter_tts: die zet bij een
/// spraakfout (een zin die wordt afgebroken, of een browser zonder stemmen) de
/// JS-foutcode door een method channel -- een ongevangen "Invalid argument" --
/// en rondt de zin waarop gewacht wordt nooit af, zodat elke volgende zin stil
/// blijft.
class WebStem implements Stem {
  var _taal = 'nl-NL';
  var _wachtrij = Future<void>.value();

  @override
  Future<void> begin(String taal) async => _taal = taal;

  @override
  void zeg(String zin) {
    _wachtrij = _wachtrij.then((_) => _spreek(zin)).catchError((Object _) {});
  }

  Future<void> _spreek(String zin) {
    final klaar = Completer<void>();
    void af(web.Event _) {
      if (!klaar.isCompleted) klaar.complete();
    }

    final uiting = web.SpeechSynthesisUtterance(zin)
      ..lang = _taal
      ..onend = af.toJS
      ..onerror = af.toJS;
    web.window.speechSynthesis.speak(uiting);
    return klaar.future.timeout(maxSpreekduur(zin), onTimeout: () {});
  }

  @override
  Future<void> stop() async {
    _wachtrij = Future<void>.value();
    web.window.speechSynthesis.cancel();
  }
}
