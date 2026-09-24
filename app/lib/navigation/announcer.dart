import 'dart:math';

import '../models/profile.dart';
import '../models/route.dart';
import 'route_tracker.dart';

/// Decides what is said when. Valhalla provides the sentences; this only picks
/// the moment, so every sentence is heard exactly once:
///
/// * **early** well in advance ("Turn left onto X."), only if there's enough
///   time -- if a turn closely follows the previous one, "imminent" is enough;
/// * **imminent** a few seconds before, with "Then ..." when the next one is
///   close;
/// * **after** ("Continue for 3 kilometers.") once you're through the turn.
class Announcer {
  Announcer(this.route, this.profile, {required this.withDistance});

  final RouteOption route;
  final Profile profile;

  /// Puts the distance in front of a sentence: Valhalla's "early" and
  /// "imminent" are often the same text, and hearing exactly the same thing
  /// twice sounds like a bug.
  final String Function(double meters, String sentence) withDistance;
  final _spoken = <(int, _Kind)>{};
  bool _started = false;

  /// What has to be said in this state, in order. [speed] in m/s.
  List<String> at(NavStatus status, double speed) {
    final sentences = <String>[];
    final m = route.maneuvers;
    if (m.isEmpty) return sentences;

    void say(int index, _Kind kind, String? sentence) {
      if (_spoken.add((index, kind)) &&
          sentence != null &&
          sentence.isNotEmpty) {
        sentences.add(sentence);
        // "Then, in 400 meters, ..." was already in it: no early one again.
        if (kind == _Kind.imminent && m[index].withNext) {
          _spoken.add((index + 1, _Kind.early));
        }
      }
    }

    // The departure: the first maneuver already describes where you're heading
    // and what comes next.
    if (!_started) {
      _started = true;
      say(0, _Kind.imminent, m.first.voiceImminent);
      _spoken.add((0, _Kind.after));
      // Not what's already behind you (a recalculation en route).
      for (var i = 1; i < status.next; i++) {
        for (final kind in _Kind.values) {
          _spoken.add((i, kind));
        }
      }
    }

    // Just through a turn: how it continues.
    final previous = status.next - 1;
    if (previous > 0 && !status.arrived) {
      for (final kind in [_Kind.early, _Kind.imminent]) {
        _spoken.add((previous, kind));
      }
      say(previous, _Kind.after, m[previous].voiceAfter);
    }

    final next = m[status.next];
    final distance = status.toNext;
    if (status.arrived && next.isDestination) {
      say(status.next, _Kind.early, null);
      say(status.next, _Kind.imminent, next.voiceImminent);
      return sentences;
    }
    // The destination itself only on arrival: "You have arrived" while you're
    // still 8 seconds away is wrong.
    final imminent = next.isDestination && status.next == m.length - 1
        ? -1.0
        : imminentDistance(speed);
    if (distance <= imminent) {
      _spoken.add((status.next, _Kind.early));
      say(status.next, _Kind.imminent, next.voiceImminent);
    } else {
      final early = earlyDistance(speed);
      // Only within the window: if you only enter it at 60% of the distance (a
      // short stretch after the previous turn), it's too late for "early".
      if (distance <= early && distance >= early * 0.6) {
        final sentence = next.voiceEarly;
        say(
          status.next,
          _Kind.early,
          sentence == null ? null : withDistance(distance, sentence),
        );
      }
    }
    return sentences;
  }

  /// Well in advance: about 35 seconds, within limits per mode of transport.
  double earlyDistance(double speed) {
    final (low, high) = switch (profile) {
      Profile.car => (300.0, 1500.0),
      Profile.bike => (120.0, 300.0),
      Profile.walk => (50.0, 120.0),
    };
    return (speed * 35).clamp(low, high);
  }

  /// Imminent: about 8 seconds, with a minimum for when you're standing still.
  double imminentDistance(double speed) {
    final minimum = switch (profile) {
      Profile.car => 60.0,
      Profile.bike => 30.0,
      Profile.walk => 15.0,
    };
    return max(minimum, speed * 8 + 15);
  }
}

enum _Kind { early, imminent, after }
