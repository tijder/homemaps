import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/utils/timed_speed_limits.dart';

void main() {
  // As the importer returns them: A27 near Eemnes (130 after 7 pm), a road with
  // a rush-hour rule on weekdays only, and a night rule that starts on
  // Friday.
  final times = TimedSpeedLimits.fromJson({
    'ways': {
      '7014267': [
        [
          130,
          127,
          [
            [1140, 360],
          ],
        ],
      ],
      '2': [
        [
          80,
          31,
          [
            [420, 540],
            [960, 1140],
          ],
        ],
      ],
      '3': [
        [
          50,
          16,
          [
            [1320, 360],
          ],
        ],
      ],
      'nonsense': [
        [130, 127, []],
      ],
      '4': 'not a list',
    },
  });

  // 28 September 2026 is a Monday.
  DateTime at(int day, int hour, int minute) =>
      DateTime(2026, 9, 27 + day, hour, minute);

  test('130 after 7 pm, until 6 am', () {
    expect(times.limitAt(7014267, 100, at(1, 18, 59)), 100);
    expect(times.limitAt(7014267, 100, at(1, 19, 0)), 130);
    expect(times.limitAt(7014267, 100, at(2, 5, 59)), 130);
    expect(times.limitAt(7014267, 100, at(2, 6, 0)), 100);
    // Another way, or none: just the normal one.
    expect(times.limitAt(99, 100, at(1, 22, 0)), 100);
    expect(times.limitAt(null, 100, at(1, 22, 0)), 100);
  });

  test('on weekdays in rush hour, not at the weekend', () {
    expect(times.limitAt(2, 100, at(1, 8, 0)), 80); // Monday
    expect(times.limitAt(2, 100, at(5, 17, 30)), 80); // Friday
    expect(times.limitAt(2, 100, at(5, 12, 0)), 100);
    expect(times.limitAt(2, 100, at(6, 8, 0)), 100); // Saturday
  });

  test('across midnight: the day the window starts counts', () {
    // Friday 22:00 to Saturday 06:00.
    expect(times.limitAt(3, 80, at(5, 23, 0)), 50);
    expect(times.limitAt(3, 80, at(6, 3, 0)), 50);
    // Friday morning belongs to Thursday night, and that doesn't count.
    expect(times.limitAt(3, 80, at(5, 3, 0)), 80);
  });

  test('what is invalid is skipped', () {
    expect(TimedSpeedLimits.fromJson(null).isEmpty, isTrue);
    expect(TimedSpeedLimits.fromJson({'ways': 'x'}).isEmpty, isTrue);
    expect(times.limitAt(4, 70, at(1, 22, 0)), 70);
  });
}
