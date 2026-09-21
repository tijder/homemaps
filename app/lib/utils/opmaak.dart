String afstand(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  if (meters < 10000) return '${(meters / 1000).toStringAsFixed(1)} km';
  return '${(meters / 1000).round()} km';
}

/// "12 min", "1 u 05".
String duur(double seconden) {
  final minuten = (seconden / 60).round();
  if (minuten < 60) return '$minuten min';
  return '${minuten ~/ 60} u ${(minuten % 60).toString().padLeft(2, '0')}';
}
