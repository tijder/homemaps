import 'package:intl/intl.dart';

/// "650 m", "2,6 km" (in het Engels "2.6 km"), "15 km".
String afstand(double meters, [String? taal]) {
  if (meters < 1000) return '${meters.round()} m';
  if (meters < 10000) {
    return '${NumberFormat('0.0', taal).format(meters / 1000)} km';
  }
  return '${(meters / 1000).round()} km';
}

/// Een afstand die niet bij elke meter verspringt: onder de 100 m op 10 m,
/// daarboven op 50 m.
double rondAfstand(double meters) => meters < 100
    ? (meters / 10).round() * 10
    : meters < 1000
    ? (meters / 50).round() * 50
    : meters;

/// "12 min", "1 u 05".
String duur(double seconden) {
  final minuten = (seconden / 60).round();
  if (minuten < 60) return '$minuten min';
  return '${minuten ~/ 60} u ${(minuten % 60).toString().padLeft(2, '0')}';
}
