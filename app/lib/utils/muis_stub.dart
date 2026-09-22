import 'dart:math';

/// Buiten het web is er geen muis op de kaart: lang indrukken opent het menu, en
/// draaien en kantelen gaat met twee vingers.
void Function() koppelMuis(
  void Function(Point<double> opKaart, Point<double> opScherm) bijRechtsklik, {
  void Function()? bijAanraking,
}) => () {};
