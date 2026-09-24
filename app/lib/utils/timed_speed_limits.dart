/// Speed limits that depend on the time of day (OSM `maxspeed:conditional`,
/// like "130 @ (19:00-06:00)" on most motorways). Valhalla doesn't read that
/// tag; the importer extracts the rules from the OSM file, per OSM way.
class TimedSpeedLimits {
  const TimedSpeedLimits(this._ways);

  static const empty = TimedSpeedLimits({});

  final Map<int, List<TimeRule>> _ways;

  bool get isEmpty => _ways.isEmpty;

  /// From `/conditional-speeds`: `{"ways": {"<id>": [[kph, days, [[from, to]]]]}}`.
  /// Anything that doesn't look as expected is skipped.
  factory TimedSpeedLimits.fromJson(Map<String, dynamic>? json) {
    final out = <int, List<TimeRule>>{};
    final ways = json?['ways'];
    if (ways is! Map) return empty;
    for (final MapEntry(:key, :value) in ways.entries) {
      final id = int.tryParse('$key');
      if (id == null || value is! List) continue;
      final rules = [for (final rule in value) ?TimeRule.fromJson(rule)];
      if (rules.isNotEmpty) out[id] = rules;
    }
    return TimedSpeedLimits(out);
  }

  /// The limit on [way] at [time]: that of the first rule that applies then,
  /// otherwise [normal].
  int? limitAt(int? way, int? normal, DateTime time) {
    for (final rule in _ways[way] ?? const <TimeRule>[]) {
      if (rule.applies(time)) return rule.kmh;
    }
    return normal;
  }
}

/// One rule: [kmh] on [days] (bitmask, Monday = 1, Sunday = 64) within one of
/// the [windows] (minutes after midnight). A window with from > to runs past
/// midnight: it starts on one of the [days] and ends the morning after.
class TimeRule {
  const TimeRule(this.kmh, this.days, this.windows);

  final int kmh;
  final int days;
  final List<(int, int)> windows;

  static TimeRule? fromJson(Object? json) {
    if (json is! List || json.length != 3) return null;
    final [kmh, days, windows] = json;
    if (kmh is! int || days is! int || windows is! List) return null;
    final parsed = <(int, int)>[];
    for (final window in windows) {
      if (window case [final int from, final int until]) {
        parsed.add((from, until));
      }
    }
    return parsed.isEmpty ? null : TimeRule(kmh, days, parsed);
  }

  bool _appliesOn(int day) => days & (1 << ((day - 1) % 7)) != 0;

  bool applies(DateTime time) {
    final minute = time.hour * 60 + time.minute;
    final today = time.weekday; // 1 = Monday
    final yesterday = today == 1 ? 7 : today - 1;
    for (final (from, until) in windows) {
      if (from <= until) {
        if (_appliesOn(today) && minute >= from && minute < until) return true;
      } else if ((_appliesOn(today) && minute >= from) ||
          (_appliesOn(yesterday) && minute < until)) {
        return true;
      }
    }
    return false;
  }
}
