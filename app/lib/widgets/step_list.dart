import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/route.dart';
import '../utils/formatting.dart';
import 'maneuver_icon.dart';
import 'navigation_bar.dart';

/// The directions: per step the icon, what you do (short with the sign at
/// on- and off-ramps, otherwise the sentence) and a distance.
///
/// With [toNext] (en route) each step shows how far away it still is, from
/// [startIndex]; without (when planning) how long the stretch after it is.
class StepList extends StatelessWidget {
  const StepList(this.route, {this.startIndex = 0, this.toNext, super.key});

  final RouteOption route;
  final int startIndex;
  final double? toNext;

  /// The steps that get their own row, with their distance.
  @visibleForTesting
  static List<({Maneuver maneuver, double meters})> steps(
    RouteOption route, {
    int startIndex = 0,
    double? toNext,
  }) {
    final m = route.maneuvers;
    final rows = <({Maneuver maneuver, double meters})>[];
    var remaining = toNext ?? 0;
    for (var i = startIndex; i < m.length; i++) {
      final merged = rows.isNotEmpty && _withoutOwnRow(m[i], m[i - 1]);
      if (toNext != null) {
        if (!merged) rows.add((maneuver: m[i], meters: remaining));
        remaining += m[i].meters;
      } else if (merged) {
        // The stretch after it belongs to the row before.
        final previous = rows.removeLast();
        rows.add((
          maneuver: previous.maneuver,
          meters: previous.meters + m[i].meters,
        ));
      } else {
        rows.add((maneuver: m[i], meters: m[i].meters));
      }
    }
    return rows;
  }

  /// Continue (7, 8) without a sign, roundabout exit (27) after roundabout
  /// enter (26), and a second exit with the same number (Valhalla sometimes
  /// splits the exit lane in two): they say nothing the row before doesn't
  /// already say.
  static bool _withoutOwnRow(Maneuver m, Maneuver previous) =>
      ((m.type == 7 || m.type == 8) && m.roadSign == null) ||
      (m.type == 27 && previous.type == 26) ||
      (_isExit(m) &&
          _isExit(previous) &&
          m.roadSign?.exit != null &&
          m.roadSign?.exit == previous.roadSign?.exit);

  static bool _isExit(Maneuver m) => m.type == 20 || m.type == 21;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final step in steps(route, startIndex: startIndex, toNext: toNext))
          _row(step.maneuver, step.meters, l, text),
      ],
    );
  }

  Widget _row(
    Maneuver maneuver,
    double meters,
    AppLocalizations l,
    TextTheme text,
  ) {
    final roadSign = maneuver.signpost;
    final action = roadSign == null ? null : shortAction(maneuver, l);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 32, child: ManeuverIcon(maneuver)),
          const SizedBox(width: 12),
          Expanded(
            child: roadSign == null
                ? Text(maneuver.instruction)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (action != null)
                        Text(
                          action,
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 4),
                      RoadSignPanel(roadSign),
                    ],
                  ),
          ),
          if (meters > 0 || toNext != null) ...[
            const SizedBox(width: 12),
            Text(
              distance(
                toNext == null ? meters : roundDistance(meters),
                l.localeName,
              ),
              style: text.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}
