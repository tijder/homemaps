import 'dart:math';

/// Outside the web there's no mouse on the map: long-press opens the menu, and
/// rotating and tilting is done with two fingers.
void Function() attachMouse(
  void Function(Point<double> onMap, Point<double> onScreen) onRightClick, {
  void Function()? onTouch,
}) => () {};
