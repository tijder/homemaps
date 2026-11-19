import 'dart:math';

import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// "650 m", "2,6 km" (in English "2.6 km"), "15 km".
String distance(double meters, [String? language]) {
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
