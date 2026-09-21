import 'dart:math';

/// Buiten het web bestaat er geen rechtermuisknop op de kaart; lang indrukken
/// doet daar hetzelfde.
void Function() luisterNaarRechtsklik(
  void Function(Point<double> opKaart, Point<double> opScherm) bijKlik,
) => () {};
