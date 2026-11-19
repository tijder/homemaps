import 'dart:math';

import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/units.dart';

/// The units everything below formats in. The settings set it (see
/// [SettingsNotifier]); a value of its own rather than an argument, because
/// every text with a distance or a speed in it would otherwise need the
/// settings passed down to it.
Units displayUnits = Units.metric;

const _metersPerMile = 1609.344;
const _feetPerMeter = 3.28084;

/// "650 m", "2,6 km" (in English "2.6 km"), "15 km"; in miles "500 ft",
/// "1.6 mi", "15 mi".
String distance(double meters, [String? language]) {
  if (displayUnits == Units.imperial) {
    final miles = meters / _metersPerMile;
    if (miles < 0.1) {
      final feet = meters * _feetPerMeter;
      // To 50 ft, to 10 below that: "437 ft" suggests a precision that
      // isn't there.
      final step = feet < 100 ? 10 : 50;
      return '${(feet / step).round() * step} ft';
    }
    if (miles < 10) return '${NumberFormat('0.0', language).format(miles)} mi';
    return '${miles.round()} mi';
  }
  if (meters < 1000) return '${meters.round()} m';
  if (meters < 10000) {
    return '${NumberFormat('0.0', language).format(meters / 1000)} km';
  }
  return '${(meters / 1000).round()} km';
}

/// A distance that doesn't change with every meter: below 100 m to 10 m,
/// below 1 km to 50 m, above that to 100 m (shown with one decimal anyway).
double roundDistance(double meters) => meters < 100
    ? (meters / 10).round() * 10
    : meters < 1000
    ? (meters / 50).round() * 50
    : (meters / 100).round() * 100;

/// A speed in m/s as a whole number of km/h or mph.
int speedIn(double metersPerSecond) => displayUnits == Units.imperial
    ? (metersPerSecond * 3600 / _metersPerMile).round()
    : (metersPerSecond * 3.6).round();

/// A speed limit in km/h (as OpenStreetMap and NDW give it) in the units
/// shown. In mph to the nearest five, as on a sign: 100 km/h is "60", not
/// "62".
int limitIn(int kmh) => displayUnits == Units.imperial
    ? (kmh * 1000 / _metersPerMile / 5).round() * 5
    : kmh;

/// A measured speed in km/h (an average, a jam) in the units shown.
int kmhIn(num kmh) => displayUnits == Units.imperial
    ? (kmh * 1000 / _metersPerMile).round()
    : kmh.round();

/// "km/h" or "mph".
String speedUnit(AppLocalizations l) =>
    displayUnits == Units.imperial ? l.mph : l.kmh;

/// "12 min"; "1 h 05 min" in English, "1 u 05" in Dutch.
String duration(double seconds, AppLocalizations l) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return l.durationMinutes(minutes);
  return l.durationHours(
    minutes ~/ 60,
    (minutes % 60).toString().padLeft(2, '0'),
  );
}

/// The time of day at [time]; with the day in front when that isn't today
/// ("Fri 08:15"), so a trip planned for tomorrow doesn't read as today.
String timeOfDay(DateTime time, String language, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final sameDay =
      time.year == today.year &&
      time.month == today.month &&
      time.day == today.day;
  return DateFormat(sameDay ? 'HH:mm' : 'EEE HH:mm', language).format(time);
}

/// How long ago something was, in the largest unit that fits: "just now",
/// "12 minutes ago", "3 hours ago", "2 days ago".
String timeAgo(AppLocalizations l, Duration time) {
  if (time.inMinutes < 60) return l.familyMinutesAgo(max(time.inMinutes, 0));
  if (time.inHours < 24) return l.familyHoursAgo(time.inHours);
  return l.familyDaysAgo(time.inDays);
}
