import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/route.dart';
import '../navigation/navigation_provider.dart';
import '../utils/formatting.dart';
import 'maneuver_icon.dart';

/// At the top during navigation: the next maneuver, large, and the maneuver
/// after it small if it follows right after.
class NavigationHeader extends StatelessWidget {
  const NavigationHeader(this.nav, {this.onTap, super.key});

  final NavigationState nav;

  /// Tap on the header: the rest of the directions.
  final VoidCallback? onTap;

  /// If the maneuver after it comes within this many meters, it is shown too.
  static const _afterwardsWithin = 300.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final status = nav.status;
    final maneuvers = nav.route.maneuvers;

    final next = status != null && !nav.arrived && !nav.recalculating
        ? maneuvers[status.next]
        : null;
    final (Widget icon, String title, String? below) = nav.arrived
        ? (
            _icon(Icons.flag, colors),
            l.arrived,
            nav.destinations.lastOrNull?.display(l),
          )
        : nav.recalculating
        ? (_icon(Icons.sync, colors), l.recalculatingBusy, null)
        : status == null
        ? (_icon(Icons.navigation, colors), l.locationSearching, null)
        : (
            ManeuverIcon(
              maneuvers[status.next],
              size: 56,
              color: colors.onPrimaryContainer,
            ),
            distance(roundDistance(status.toNext), l.localeName),
            maneuvers[status.next].instruction,
          );
    // At an on- or off-ramp, fork or merge lane, as in Google and Apple Maps:
    // briefly what you do, with the sign below it, instead of the whole
    // sentence.
    final roadSign = next?.signpost;
    final action = roadSign == null ? null : shortAction(next!, l);
    final lanes = next == null ? null : nav.lanes;
    final matrix = nav.arrived ? null : nav.matrix;

    // After "enter roundabout" comes "exit roundabout", with the same exit:
    // that is already in the large icon. Only then what comes next.
    var afterwards = status != null && !nav.arrived && !nav.recalculating
        ? status.next + 1
        : null;
    var between = next?.meters ?? 0;
    if (afterwards != null &&
        afterwards < maneuvers.length &&
        next?.type == 26 &&
        maneuvers[afterwards].type == 27) {
      between += maneuvers[afterwards].meters;
      afterwards++;
    }
    final showAfterwards =
        afterwards != null &&
        afterwards < maneuvers.length &&
        between < _afterwardsWithin;

    return Material(
      color: colors.primaryContainer,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: text.headlineMedium?.copyWith(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (roadSign != null) ...[
                          if (action != null)
                            Text(
                              action,
                              style: text.titleMedium?.copyWith(
                                color: colors.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          const SizedBox(height: 6),
                          RoadSignPanel(roadSign),
                        ] else if (below != null)
                          Text(
                            below,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium?.copyWith(
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The MSI signs take precedence: they show what applies now.
          if (matrix != null)
            MatrixBar(matrix.perLane)
          else if (lanes != null)
            LaneBar(
              lanes.perLane,
              // A junction before the maneuver: with its own distance, otherwise
              // it looks like the turn above.
              ahead: lanes.atManeuver ? null : lanes.ahead,
            ),
          if (showAfterwards)
            Container(
              color: colors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Text(
                    l.afterwards,
                    style: text.titleSmall?.copyWith(color: colors.onPrimary),
                  ),
                  const SizedBox(width: 8),
                  ManeuverIcon(maneuvers[afterwards], color: colors.onPrimary),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Widget _icon(IconData icon, ColorScheme colors) =>
      Icon(icon, size: 56, color: colors.onPrimaryContainer);
}

/// Briefly what you do at an on- or off-ramp, fork or merge lane ("Keep
/// left"), or null for another maneuver.
String? shortAction(Maneuver maneuver, AppLocalizations l) {
  final kind = switch (maneuver.type) {
    17 || 18 || 19 => 'onRamp',
    20 || 21 => 'exit',
    22 => 'straight',
    23 => 'right',
    24 => 'left',
    25 || 37 || 38 => 'merge',
    _ => null,
  };
  return kind == null ? null : l.shortAction(kind);
}

/// A sign like along the motorway: the exit number, the road numbers (A roads
/// red, N roads yellow, as in the Netherlands) and the directions.
class RoadSignPanel extends StatelessWidget {
  const RoadSignPanel(this.roadSign, {super.key});

  final RoadSign roadSign;

  static const _blue = Color(0xFF0A4C9A);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final directions = roadSign.directions.isNotEmpty
        ? roadSign.directions.take(3).join(' · ')
        : roadSign.label;
    Widget shield(String content, Color background, Color before) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        content,
        style: text.labelLarge?.copyWith(
          color: before,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _blue,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (roadSign.exit case final exit?)
            shield(l.exit(exit), Colors.white, _blue),
          for (final road in roadSign.roads.take(2))
            if (road.startsWith('A') || road.startsWith('E'))
              shield(
                road,
                road.startsWith('E')
                    ? const Color(0xFF00843D)
                    : const Color(0xFFD2232A),
                Colors.white,
              )
            else if (road.startsWith('N'))
              shield(road, const Color(0xFFFFD200), Colors.black)
            else
              shield(road, _blue, Colors.white),
          if (directions != null)
            Text(
              directions,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

/// The lanes at a junction: correct ones solid, the rest dimmed. With [ahead]
/// the left side shows how far away that junction still is.
class LaneBar extends StatelessWidget {
  const LaneBar(this.perLane, {this.ahead, super.key});

  final List<Lane> perLane;

  /// How far away the junction still is, if it isn't the maneuver's.
  final double? ahead;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final correct = l.lanesCorrect(
      perLane.where((s) => s.correct).length,
      perLane.length,
    );
    final ahead = this.ahead;
    final distanceText = ahead == null
        ? null
        : distance(roundDistance(ahead), l.localeName);
    return Semantics(
      label: distanceText == null
          ? correct
          : l.lanesAhead(distanceText, correct),
      excludeSemantics: true,
      child: Container(
        color: colors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            if (distanceText != null)
              Text(
                distanceText,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final (i, lane) in perLane.indexed) ...[
                    if (i > 0)
                      Container(
                        width: 1,
                        height: 28,
                        color: colors.onPrimary.withValues(alpha: 0.3),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: _lane(lane, colors),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lane(Lane lane, ColorScheme colors) {
    // A correct lane with more directions: only the one you take, otherwise it
    // doesn't fit and says less.
    final directions = lane.correct && lane.usage != null
        ? [lane.usage!]
        : lane.directions.isEmpty
        ? const ['straight']
        : lane.directions;
    final color = lane.correct
        ? colors.onPrimary
        : colors.onPrimary.withValues(alpha: 0.35);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final direction in directions.take(2))
          Icon(
            laneIconData(direction),
            size: directions.length > 1 ? 22 : 30,
            color: color,
          ),
      ],
    );
  }
}

/// The next gantry with MSI signs, per lane from left to right, as it hangs
/// above the road.
class MatrixBar extends StatelessWidget {
  const MatrixBar(this.perLane, {super.key});

  /// Codes as in [Gantry]: "70", "70r", "x", "<", ">", "open", "end", "".
  final List<String> perLane;

  static const _red = Color(0xFFD32F2F);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Semantics(
      label: l.matrixSigns,
      child: Container(
        color: const Color(0xFF263238),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final lane in perLane)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _laneImage(lane),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _laneImage(String lane) {
    Icon buildIcon(IconData icon, Color color) =>
        Icon(icon, color: color, size: 28);
    const white = Colors.white;
    return switch (lane) {
      'x' => buildIcon(Icons.close, _red),
      '<' => buildIcon(Icons.south_west, white),
      '>' => buildIcon(Icons.south_east, white),
      'open' => buildIcon(Icons.arrow_downward, const Color(0xFF43A047)),
      'end' => buildIcon(Icons.block, Colors.white70),
      '' => const SizedBox.shrink(),
      _ => _speed(lane),
    };
  }

  static Widget _speed(String lane) {
    final mandatory = lane.endsWith('r');
    final numberFormat = mandatory ? lane.substring(0, lane.length - 1) : lane;
    final text = Text(
      numberFormat,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    if (!mandatory) return text;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _red, width: 3),
      ),
      child: text,
    );
  }
}

/// At the bottom during navigation: arrival time, what remains, voice and stop.
class NavigationFooter extends StatelessWidget {
  const NavigationFooter(
    this.nav, {
    super.key,
    required this.onStop,
    required this.onMute,
    this.onSearchAlong,
    this.isSharing,
    this.onShare,
  });

  final NavigationState nav;
  final VoidCallback onStop;
  final ValueChanged<bool> onMute;

  /// Location sharing: null when it is off, `false` when it is running, `true`
  /// when sending fails.
  final bool? isSharing;
  final VoidCallback? onShare;

  /// "Along the route" (fuel, charging, ...): add a stop.
  final VoidCallback? onSearchAlong;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = nav.status;
    final seconds = status?.remainingSeconds ?? nav.route.seconds;
    final meters = status?.remainingMeters ?? nav.route.meters;
    final arrival = DateTime.now().add(Duration(seconds: seconds.round()));
    final language = Localizations.localeOf(context).languageCode;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: nav.arrived
                  ? Text(l.arrived, style: text.titleLarge)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l.arrival(DateFormat.Hm(language).format(arrival)),
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${duration(seconds)} · ${distance(meters, l.localeName)}',
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
            ),
            if (!nav.arrived && onSearchAlong != null)
              IconButton(
                tooltip: l.alongTheRoute,
                icon: const Icon(Icons.local_gas_station_outlined),
                onPressed: onSearchAlong,
              ),
            if (!nav.arrived && isSharing != null)
              IconButton(
                tooltip: l.locationSharing,
                icon: Icon(
                  Icons.share_location,
                  color: isSharing! ? const Color(0xFFE65100) : null,
                ),
                onPressed: onShare,
              ),
            if (!nav.arrived)
              IconButton(
                tooltip: nav.muted ? l.voiceOn : l.voiceOff,
                icon: Icon(nav.muted ? Icons.volume_off : Icons.volume_up),
                onPressed: () => onMute(!nav.muted),
              ),
            const SizedBox(width: 4),
            FilledButton.icon(
              style: nav.arrived
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
              onPressed: onStop,
              icon: Icon(nav.arrived ? Icons.check : Icons.close),
              label: Text(nav.arrived ? l.done : l.stopNavigation),
            ),
          ],
        ),
      ),
    );
  }
}

/// A faster route en route: take it or ignore it. A bar runs empty until the
/// suggestion expires by itself (then the current route stays).
class SuggestionCard extends StatelessWidget {
  const SuggestionCard(
    this.suggestion, {
    super.key,
    required this.onAccept,
    required this.onIgnore,
  });

  final Suggestion suggestion;
  final VoidCallback onAccept;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final remaining = suggestion.expires.difference(DateTime.now());
    final minutes = (suggestion.secondsFaster / 60).round();
    final via = suggestion.via;
    return Material(
      elevation: 8,
      color: colors.tertiaryContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // From full to empty in the time the suggestion has left.
          TweenAnimationBuilder<double>(
            tween: Tween(
              begin:
                  remaining.inMilliseconds /
                  NavigationNotifier.suggestionDuration.inMilliseconds,
              end: 0,
            ),
            duration: remaining.isNegative ? Duration.zero : remaining,
            builder: (context, value, _) =>
                LinearProgressIndicator(value: value.clamp(0, 1), minHeight: 3),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
            child: Row(
              children: [
                Icon(Icons.alt_route, color: colors.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.suggestionFaster(minutes),
                        style: text.titleMedium?.copyWith(
                          color: colors.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (via != null)
                        Text(
                          l.suggestionVia(via),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                            color: colors.onTertiaryContainer,
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton(onPressed: onIgnore, child: Text(l.ignore)),
                const SizedBox(width: 4),
                FilledButton(onPressed: onAccept, child: Text(l.accept)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom left during car navigation: the traffic sign with the speed limit
/// (if known) and your own speed, red if you are well over it. A temporary
/// limit (at roadworks) gets a roadworks icon; a limit from the MSI signs is
/// white on black, as above the road.
class SpeedLimitSign extends StatelessWidget {
  const SpeedLimitSign({
    super.key,
    required this.limit,
    required this.speed,
    this.source = LimitSource.osm,
  });

  final int? limit;
  final LimitSource source;

  /// In m/s, or null if unknown.
  final double? speed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final kmh = speed == null ? null : (speed! * 3.6).round();
    final speeding = limit != null && kmh != null && kmh > limit! + 5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (limit != null)
          Semantics(
            label: switch (source) {
              LimitSource.roadworks => l.speedLimitTemporary(limit!),
              LimitSource.msi => l.speedLimitMatrix(limit!),
              _ => l.speedLimit(limit!),
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: source == LimitSource.msi
                        ? Colors.black
                        : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFD32F2F),
                      width: 6,
                    ),
                    boxShadow: const [
                      BoxShadow(blurRadius: 4, color: Colors.black26),
                    ],
                  ),
                  child: Text(
                    '$limit',
                    style: TextStyle(
                      color: source == LimitSource.msi
                          ? Colors.white
                          : Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (source == LimitSource.roadworks)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9A825),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.construction,
                        size: 14,
                        color: Colors.black,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (kmh != null) ...[
          const SizedBox(height: 6),
          Material(
            elevation: 4,
            color: speeding ? colors.error : colors.surface,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Column(
                children: [
                  Text(
                    '$kmh',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: speeding ? colors.onError : colors.onSurface,
                    ),
                  ),
                  Text(
                    l.kmh,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: speeding ? colors.onError : colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
