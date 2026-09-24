import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

/// Two things maplibre-gl-js does differently from what this app wants, both
/// solved by getting in front of the map in the capture phase:
///
/// * **Right mouse button = the point menu.** maplibre_gl has no right-click on
///   the web ("long press" is a double-click there), so we listen to
///   `contextmenu` ourselves.
/// * **Rotate and tilt with the middle mouse button**, not the right one. In
///   maplibre-gl-js that's hardwired to button 2 (`e.button===2`, and while
///   dragging `buttons & 2`), with no setting. So a right-drag is blocked and a
///   middle-drag is passed on as a right-drag: the same event, recreated with
///   different button numbers.
///
/// In addition [onTouch] reports every touch of the map (mouse, finger, scroll
/// wheel), so navigation knows you're looking around yourself.
///
/// Returns a function that detaches everything again.
void Function() attachMouse(
  void Function(Point<double> onMap, Point<double> onScreen) onRightClick, {
  void Function()? onTouch,
}) {
  web.Element? mapOf(web.Event event) {
    final target = event.target;
    if (target == null || !target.isA<web.Element>()) return null;
    return (target as web.Element).closest('.maplibregl-map');
  }

  void rightClick(web.Event event) {
    final mouse = event as web.MouseEvent;
    final map = mapOf(mouse);
    if (map == null) return;
    // Otherwise the browser's menu appears on top of it.
    mouse.preventDefault();
    final rect = map.getBoundingClientRect();
    onRightClick(
      Point(mouse.clientX - rect.left, mouse.clientY - rect.top),
      Point(mouse.clientX.toDouble(), mouse.clientY.toDouble()),
    );
  }

  // The element the middle-drag started on; the recreated events go there,
  // even if the mouse has since left the map.
  web.EventTarget? dragTarget;
  var busy = false; // a recreated event must not be translated again

  void forward(web.MouseEvent source, String kind, {required int buttons}) {
    busy = true;
    try {
      dragTarget?.dispatchEvent(
        web.MouseEvent(
          kind,
          web.MouseEventInit(
            bubbles: true,
            cancelable: true,
            view: web.window,
            clientX: source.clientX,
            clientY: source.clientY,
            screenX: source.screenX,
            screenY: source.screenY,
            button: 2,
            buttons: buttons,
          ),
        ),
      );
    } finally {
      busy = false;
    }
  }

  void mouseDown(web.Event event) {
    if (busy) return;
    final mouse = event as web.MouseEvent;
    if (mapOf(mouse) == null) return;
    if (mouse.button == 2) {
      // No rotating with the right button. `contextmenu` is a separate event
      // and still comes.
      mouse.stopPropagation();
    } else if (mouse.button == 1) {
      // preventDefault: otherwise the browser starts its autoscroll.
      mouse.preventDefault();
      mouse.stopPropagation();
      dragTarget = mouse.target;
      forward(mouse, 'mousedown', buttons: 2);
    }
  }

  void move(web.Event event) {
    if (busy || dragTarget == null) return;
    final mouse = event as web.MouseEvent;
    mouse.stopPropagation();
    forward(mouse, 'mousemove', buttons: 2);
  }

  void mouseUp(web.Event event) {
    if (busy || dragTarget == null) return;
    final mouse = event as web.MouseEvent;
    if (mouse.button != 1) return;
    mouse.stopPropagation();
    forward(mouse, 'mouseup', buttons: 0);
    dragTarget = null;
  }

  void touched(web.Event event) {
    if (busy || onTouch == null) return;
    if (mapOf(event) != null) onTouch();
  }

  final listeners = <String, JSFunction>{
    'pointerdown': touched.toJS,
    'wheel': touched.toJS,
    'contextmenu': rightClick.toJS,
    'mousedown': mouseDown.toJS,
    'mousemove': move.toJS,
    'mouseup': mouseUp.toJS,
  };
  // On window and in the capture phase: maplibre itself listens on window for
  // mousemove and mouseup, and we have to be first.
  for (final MapEntry(key: kind, value: listener) in listeners.entries) {
    web.window.addEventListener(kind, listener, true.toJS);
  }
  return () {
    for (final MapEntry(key: kind, value: listener) in listeners.entries) {
      web.window.removeEventListener(kind, listener, true.toJS);
    }
  };
}
