import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

/// Twee dingen die maplibre-gl-js anders doet dan deze app wil, allebei opgelost
/// door in de capture-fase vóór de kaart te gaan zitten:
///
/// * **Rechtermuisknop = het puntmenu.** maplibre_gl kent op het web geen
///   rechtermuisklik ("lang indrukken" is daar een dubbelklik), dus luisteren we
///   zelf naar `contextmenu`.
/// * **Draaien en kantelen met de middelste muisknop**, niet met de rechter. In
///   maplibre-gl-js zit dat hard op knop 2 (`e.button===2`, en tijdens het slepen
///   `buttons & 2`), zonder instelling. Een rechtersleep wordt daarom tegengehouden
///   en een middelsleep wordt als rechtersleep doorgegeven: dezelfde gebeurtenis,
///   nagemaakt met andere knopnummers.
///
/// Geeft een functie terug die alles weer loskoppelt.
void Function() koppelMuis(
  void Function(Point<double> opKaart, Point<double> opScherm) bijRechtsklik,
) {
  web.Element? kaartVan(web.Event gebeurtenis) {
    final doel = gebeurtenis.target;
    if (doel == null || !doel.isA<web.Element>()) return null;
    return (doel as web.Element).closest('.maplibregl-map');
  }

  void rechtsklik(web.Event gebeurtenis) {
    final muis = gebeurtenis as web.MouseEvent;
    final kaart = kaartVan(muis);
    if (kaart == null) return;
    // Anders komt het menu van de browser eroverheen.
    muis.preventDefault();
    final vak = kaart.getBoundingClientRect();
    bijRechtsklik(
      Point(muis.clientX - vak.left, muis.clientY - vak.top),
      Point(muis.clientX.toDouble(), muis.clientY.toDouble()),
    );
  }

  // Het element waarop de middelsleep begon; de nagemaakte gebeurtenissen gaan
  // daarheen, ook als de muis intussen buiten de kaart is.
  web.EventTarget? sleepDoel;
  var bezig =
      false; // een nagemaakte gebeurtenis mag niet opnieuw vertaald worden

  void stuurDoor(web.MouseEvent bron, String soort, {required int knoppen}) {
    bezig = true;
    try {
      sleepDoel?.dispatchEvent(
        web.MouseEvent(
          soort,
          web.MouseEventInit(
            bubbles: true,
            cancelable: true,
            view: web.window,
            clientX: bron.clientX,
            clientY: bron.clientY,
            screenX: bron.screenX,
            screenY: bron.screenY,
            button: 2,
            buttons: knoppen,
          ),
        ),
      );
    } finally {
      bezig = false;
    }
  }

  void omlaag(web.Event gebeurtenis) {
    if (bezig) return;
    final muis = gebeurtenis as web.MouseEvent;
    if (kaartVan(muis) == null) return;
    if (muis.button == 2) {
      // Geen draaien met rechts. `contextmenu` is een eigen gebeurtenis en komt
      // gewoon nog.
      muis.stopPropagation();
    } else if (muis.button == 1) {
      // preventDefault: anders start de browser zijn automatisch scrollen.
      muis.preventDefault();
      muis.stopPropagation();
      sleepDoel = muis.target;
      stuurDoor(muis, 'mousedown', knoppen: 2);
    }
  }

  void beweeg(web.Event gebeurtenis) {
    if (bezig || sleepDoel == null) return;
    final muis = gebeurtenis as web.MouseEvent;
    muis.stopPropagation();
    stuurDoor(muis, 'mousemove', knoppen: 2);
  }

  void omhoog(web.Event gebeurtenis) {
    if (bezig || sleepDoel == null) return;
    final muis = gebeurtenis as web.MouseEvent;
    if (muis.button != 1) return;
    muis.stopPropagation();
    stuurDoor(muis, 'mouseup', knoppen: 0);
    sleepDoel = null;
  }

  final luisteraars = <String, JSFunction>{
    'contextmenu': rechtsklik.toJS,
    'mousedown': omlaag.toJS,
    'mousemove': beweeg.toJS,
    'mouseup': omhoog.toJS,
  };
  // Op window en in de capture-fase: maplibre luistert zelf op window naar
  // mousemove en mouseup, en wij moeten eerder zijn.
  for (final MapEntry(key: soort, value: luisteraar) in luisteraars.entries) {
    web.window.addEventListener(soort, luisteraar, true.toJS);
  }
  return () {
    for (final MapEntry(key: soort, value: luisteraar) in luisteraars.entries) {
      web.window.removeEventListener(soort, luisteraar, true.toJS);
    }
  };
}
