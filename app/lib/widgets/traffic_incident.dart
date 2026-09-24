import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../utils/formatting.dart';

/// What is going on at a tapped part of the traffic layer. The properties come
/// from the importer: codes from NDW's feed, translated here.
class TrafficIncident extends StatelessWidget {
  const TrafficIncident(this.properties, {super.key});

  final Map<String, dynamic> properties;

  /// Title and the lines below it; separate from [build] so it can be tested.
  static (String, List<String>) text(
    AppLocalizations l,
    String language,
    Map<String, dynamic> info,
  ) {
    final kind = info['kind'];
    final lines = <String>[];
    if (kind case 'accident' || 'breakdown' || 'obstacle') {
      final since = DateTime.tryParse(info['since'] as String? ?? '');
      if (since != null) {
        lines.add(
          l.incidentSince(DateFormat.Hm(language).format(since.toLocal())),
        );
      }
      return (
        switch (kind) {
          'accident' => l.incidentAccident,
          'breakdown' => l.incidentBreakdown,
          _ => l.incidentObstacle,
        },
        lines,
      );
    }
    if (kind == 'jam' || kind == 'slow') {
      final delay = (info['delay_s'] as num?)?.toDouble() ?? 0;
      lines.add(
        l.trafficDelay(duration(delay), (info['kph'] as num?)?.toInt() ?? 0),
      );
      return (kind == 'jam' ? l.trafficJam : l.trafficSlow, lines);
    }
    final title = kind == 'roadworks'
        ? l.trafficLaneClosed
        : info['whole_road'] == true
        ? l.trafficRoadClosed
        : switch (info['carriageway']) {
            'exitSlipRoad' => l.trafficExitClosed,
            'entrySlipRoad' => l.trafficOnRampClosed,
            'connectingCarriageway' => l.trafficConnectingRoadClosed,
            'parallelCarriageway' => l.trafficParallelRoadClosed,
            _ => l.trafficCarriagewayClosed,
          };
    final open = (info['lanes_open'] as num?)?.toInt();
    if (kind == 'roadworks' && open != null && open > 0) {
      lines.add(l.trafficLanesOpen(open));
    }
    final cause = switch (info['cause']) {
      'roadMaintenance' || 'constructionWork' => l.causeRoadworks,
      'accident' => l.causeAccident,
      'publicEvent' => l.causeEvent,
      _ => null,
    };
    if (cause != null) lines.add(cause);
    final until = DateTime.tryParse(info['until'] as String? ?? '');
    if (until != null) {
      lines.add(
        l.trafficUntil(
          DateFormat('EEE d MMM HH:mm', language).format(until.toLocal()),
        ),
      );
    }
    return (title, lines);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final (title, lines) = text(l, language, properties);
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.titleMedium),
          for (final line in lines) ...[
            const SizedBox(height: 4),
            Text(line, style: theme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
