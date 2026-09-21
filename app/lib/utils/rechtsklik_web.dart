import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

/// maplibre_gl kent op het web geen rechtermuisklik ("lang indrukken" is daar een
/// dubbelklik), dus luisteren we zelf naar `contextmenu` op de kaart. Geeft de
/// plek binnen de kaart (voor toLatLng) en op het scherm (voor het menu), en een
/// functie terug om het luisteren te stoppen.
void Function() luisterNaarRechtsklik(
  void Function(Point<double> opKaart, Point<double> opScherm) bijKlik,
) {
  void verwerk(web.Event gebeurtenis) {
    final muis = gebeurtenis as web.MouseEvent;
    final doel = muis.target;
    if (doel == null || !doel.isA<web.Element>()) return;
    final kaart = (doel as web.Element).closest('.maplibregl-map');
    if (kaart == null) return;
    // Anders komt het menu van de browser eroverheen.
    muis.preventDefault();
    final vak = kaart.getBoundingClientRect();
    bijKlik(
      Point(muis.clientX - vak.left, muis.clientY - vak.top),
      Point(muis.clientX.toDouble(), muis.clientY.toDouble()),
    );
  }

  final luisteraar = verwerk.toJS;
  // In de capture-fase: de kaart zelf slikt de gebeurtenis anders in.
  web.document.addEventListener('contextmenu', luisteraar, true.toJS);
  return () =>
      web.document.removeEventListener('contextmenu', luisteraar, true.toJS);
}
