import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../l10n/app_localizations.dart';
import 'along_route_search.dart';
import 'location_reason.dart';
import 'route_preferences.dart';
import '../models/place.dart';
import '../models/route.dart';
import '../providers/location.dart';
import '../providers/planner.dart';
import '../services/valhalla_service.dart';
import '../utils/planned_closures.dart';
import '../utils/formatting.dart';
import 'elevation_profile.dart';
import 'step_list.dart';
import 'search_field.dart';

/// The panel next to (wide screen) or below (narrow screen) the map: the
/// points, the mode of transport, the options and the outcome.
///
/// Narrow ([compact]) and with a complete route the outcome comes first: one
/// line "from → to" (tap to edit), then the routes and Start. The fields only
/// come back when you start editing, and collapse again as soon as the route
/// is complete.
class RoutePanel extends ConsumerStatefulWidget {
  const RoutePanel({
    super.key,
    required this.near,
    this.myLocation,
    this.onNavigate,
    this.onEnableLocation,
    this.scroll,
    this.compact = false,
  });

  final LatLng? Function() near;

  /// See [SearchField.myLocation].
  final Future<Place?> Function()? myLocation;

  /// "Start": navigate the chosen route.
  final ValueChanged<RouteOption>? onNavigate;

  /// Turns your location on (with the permission prompt): only then can you
  /// navigate.
  final VoidCallback? onEnableLocation;
  final ScrollController? scroll;

  /// In the bottom sheet of a narrow screen.
  final bool compact;

  @override
  ConsumerState<RoutePanel> createState() => _RoutePanelState();
}

class _RoutePanelState extends ConsumerState<RoutePanel> {
  /// Narrow: the fields are open. Automatically as long as the route is
  /// incomplete.
  late bool _editing = !ref.read(plannerProvider).complete;

  void _setEditing(bool enabled) {
    setState(() => _editing = enabled);
    // Back to the top: otherwise the summary or the first field is out of
    // view.
    final scroll = widget.scroll;
    if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    // Became complete (the last point chosen): collapse. Incomplete again
    // (a point cleared): open.
    ref.listen(plannerProvider.select((p) => p.complete), (old, newValue) {
      if (newValue != old) _setEditing(!newValue);
    });
    final planner = ref.watch(plannerProvider);
    final collapsed = widget.compact && planner.complete && !_editing;

    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: collapsed
          ? [
              _summary(planner),
              const SizedBox(height: 4),
              _outcome(planner),
              const Divider(height: 24),
              _profile(),
              _departure(planner),
              _options(),
              _details(planner),
            ]
          : [
              _header(planner),
              const SizedBox(height: 4),
              _profile(),
              _departure(planner),
              const SizedBox(height: 4),
              _fields(planner),
              _viaRow(),
              _options(),
              const Divider(),
              _outcome(planner),
              _details(planner),
            ],
    );
  }

  Widget _header(PlannerState planner) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        IconButton(
          tooltip: l.backToSearch,
          onPressed: ref.read(plannerProvider.notifier).toSearch,
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(l.route, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (widget.compact && planner.complete)
          TextButton(onPressed: () => _setEditing(false), child: Text(l.done)),
      ],
    );
  }

  /// One line: from → to (and how many waypoints), tap to edit.
  Widget _summary(PlannerState planner) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final points = [for (final p in planner.points) p.place!];
    final vias = points.length - 2;
    return Row(
      children: [
        IconButton(
          tooltip: l.backToSearch,
          onPressed: ref.read(plannerProvider.notifier).toSearch,
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _setEditing(true),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${points.first.display(l)} → '
                          '${points.last.display(l)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium,
                        ),
                        if (vias > 0)
                          Text(l.stopCount(vias), style: text.bodySmall),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: l.editRoute,
                    child: const Icon(Icons.edit_outlined, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _profile() => const ProfileChoice();

  /// "Now" or "Later": a day in the coming week and a time.
  Widget _departure(PlannerState planner) {
    final l = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final later = planner.departure;
    Widget withInterceptor(BuildContext _, Widget? kind) =>
        PointerInterceptor(child: kind!);
    Future<void> choose() async {
      final now = DateTime.now();
      final day = await showDatePicker(
        context: context,
        firstDate: DateUtils.dateOnly(now),
        lastDate: now.add(const Duration(days: 7)),
        initialDate: later ?? now,
        builder: withInterceptor,
      );
      if (day == null || !mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(
          later ?? now.add(const Duration(hours: 1)),
        ),
        builder: withInterceptor,
      );
      if (time == null || !mounted) return;
      ref
          .read(plannerProvider.notifier)
          .setDeparture(
            DateTime(day.year, day.month, day.day, time.hour, time.minute),
          );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 20),
          const SizedBox(width: 8),
          Text(l.departure),
          const SizedBox(width: 12),
          ChoiceChip(
            label: Text(l.departNow),
            selected: later == null,
            onSelected: (_) =>
                ref.read(plannerProvider.notifier).setDeparture(null),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(
              later == null
                  ? l.departLater
                  : DateFormat('EEE d MMM HH:mm', language).format(later),
            ),
            selected: later != null,
            onSelected: (_) => choose(),
          ),
        ],
      ),
    );
  }

  Widget _fields(PlannerState planner) {
    final l = AppLocalizations.of(context);
    final actions = ref.read(plannerProvider.notifier);
    final latest = planner.points.length - 1;
    // Dragging by the handle changes the order. The key is the point's id, so
    // each field takes its own text and suggestions along.
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: planner.points.length,
      onReorderItem: actions.reorder,
      itemBuilder: (context, i) {
        final point = planner.points[i];
        return Padding(
          key: ValueKey(point.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: SearchField(
            label: i == 0 ? l.from : (i == latest ? l.to : l.via),
            icon: i == 0
                ? Icons.trip_origin
                : (i == latest ? Icons.place : Icons.more_vert),
            place: point.place,
            near: widget.near,
            myLocation: widget.myLocation,
            onChosen: (chosen) => actions.setPoint(i, chosen),
            onCleared: () => actions.remove(i),
            before: ReorderableDragStartListener(
              index: i,
              child: Tooltip(
                message: l.dragToReorder,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.drag_indicator),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _viaRow() {
    final l = AppLocalizations.of(context);
    final actions = ref.read(plannerProvider.notifier);
    return Row(
      children: [
        TextButton.icon(
          onPressed: actions.addVia,
          icon: const Icon(Icons.add),
          label: Text(l.addViaLabel),
        ),
        const Spacer(),
        IconButton(
          tooltip: l.swapEnds,
          onPressed: actions.swap,
          icon: const Icon(Icons.swap_vert),
        ),
        IconButton(
          tooltip: l.clearRoute,
          onPressed: actions.toSearch,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  Widget _options() {
    final l = AppLocalizations.of(context);
    return ExpansionTile(
      title: Text(l.options),
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      shape: const Border(),
      children: const [RoutePreferences(dense: true)],
    );
  }

  /// The routes (or what went wrong) and Start.
  Widget _outcome(PlannerState planner) {
    final l = AppLocalizations.of(context);
    final closures = ref.watch(closuresOnRoutesProvider);
    final actions = ref.read(plannerProvider.notifier);
    return planner.routes.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(l.routeCalculating),
          ],
        ),
      ),
      error: (error, _) => _ErrorMessage(error: error),
      data: (routes) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, route) in routes.indexed)
            _RouteCard(
              route: route,
              title: i == 0 ? l.fastest : l.alternative(i),
              chosen: i == planner.chosen,
              onTap: () => actions.choose(i, moveView: true),
              closures: closures != null && i < closures.length
                  ? closures[i]
                  : const [],
            ),
          if (planner.chosenRoute case final route?
              when widget.onNavigate != null) ...[
            const SizedBox(height: 8),
            _StartButton(
              onStart: () => widget.onNavigate!(route),
              onEnableLocation: widget.onEnableLocation,
            ),
          ],
          if (planner.chosenRoute case final route?) ...[
            const SizedBox(height: 12),
            AlongRouteSearch(
              // A different route is a new search.
              key: ObjectKey(route),
              line: route.points,
              onChosen: actions.addVia,
            ),
          ],
        ],
      ),
    );
  }

  /// Elevation profile and directions of the chosen route.
  Widget _details(PlannerState planner) {
    final l = AppLocalizations.of(context);
    final route = planner.routes.value == null ? null : planner.chosenRoute;
    if (route == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (route.elevations.length > 1) ...[
          const SizedBox(height: 8),
          Text(
            l.elevationProfile,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          ElevationProfile(elevations: route.elevations),
        ],
        const SizedBox(height: 12),
        Text(l.instructions, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        StepList(route),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.route,
    required this.title,
    required this.chosen,
    required this.onTap,
    this.closures = const [],
  });

  final RouteOption route;

  /// Planned closures on this route (only when leaving later).
  final List<ClosureOnRoute> closures;
  final String title;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final arrival = DateTime.now().add(
      Duration(seconds: route.seconds.round()),
    );
    final language = Localizations.localeOf(context).languageCode;
    final via = mainRoads(route);
    final extra = [
      if (via.isNotEmpty) l.suggestionVia(via.join(', ')),
      l.arrivalAt(DateFormat.Hm(language).format(arrival)),
      if (route.elevations.length > 1)
        l.ascentDescent(route.ascent.round(), route.descent.round()),
      if (route.hasToll) l.withToll,
      if (route.hasFerry) l.withFerry,
    ];
    return Card(
      elevation: 0,
      color: chosen ? colors.primaryContainer : colors.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onTap: onTap,
            title: Text(
              '${duration(route.seconds)} · ${distance(route.meters, l.localeName)}',
            ),
            subtitle: Text([title, ...extra].join(' · ')),
            selected: chosen,
            trailing: _delay(context, route),
          ),
          if (closures.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber, size: 18, color: colors.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.closureOnRoute(
                        _window(context, closures.first),
                        closures.length,
                      ),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.error),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _window(BuildContext context, ClosureOnRoute window) {
    final language = Localizations.localeOf(context).languageCode;
    final format = DateFormat('EEE HH:mm', language);
    final from = format.format(window.from.toLocal());
    final until = window.until;
    return until == null ? from : '$from – ${format.format(until.toLocal())}';
  }
}

/// "+9 min delay" on the right of the card, if traffic adds a minute or more.
/// Red when it is a lot (ten minutes, or a quarter of the trip), otherwise
/// orange.
Widget? _delay(BuildContext context, RouteOption route) {
  final seconds = route.delay;
  if (seconds < 60) return null;
  final l = AppLocalizations.of(context);
  final large = seconds >= 600 || seconds >= route.seconds * 0.25;
  final color = large
      ? Theme.of(context).colorScheme.error
      : const Color(0xFFE65100);
  final text = Theme.of(context).textTheme;
  return Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text(
        '+${duration(seconds)}',
        style: text.titleSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      Text(l.delay, style: text.bodySmall?.copyWith(color: color)),
    ],
  );
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = switch (error) {
      RouteError(code: 171) => l.noRoadNearby,
      RouteError(code: 0) => l.serverUnreachable,
      RouteError() => l.noRoute,
      _ => l.serverUnreachable,
    };
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// "Start" is only possible with a known location. Otherwise it says why not,
/// and where possible a button to fix it -- never a button that does nothing.
class _StartButton extends ConsumerWidget {
  const _StartButton({required this.onStart, this.onEnableLocation});

  final VoidCallback onStart;
  final VoidCallback? onEnableLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final location = ref.watch(locationProvider);
    final start = FilledButton.icon(
      onPressed: location.fix != null ? onStart : null,
      icon: location.status == LocationStatus.searching
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.navigation),
      label: Text(
        location.status == LocationStatus.searching
            ? l.locationSearching
            : l.startNavigation,
      ),
    );
    if (location.fix != null || location.status == LocationStatus.searching) {
      return start;
    }
    if (location.status == LocationStatus.off) {
      return FilledButton.tonalIcon(
        onPressed: onEnableLocation,
        icon: const Icon(Icons.my_location),
        label: Text(l.locationEnableToNavigate),
      );
    }
    final reason = locationReason(l, location.status);
    // Denied once, the question can be asked again; with "never" and a
    // disabled service it has to go through the settings.
    final again =
        location.status == LocationStatus.denied ||
        location.status == LocationStatus.notFound;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        start,
        if (reason != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${l.navigatingWithoutLocation} $reason',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (again && onEnableLocation != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onEnableLocation,
              child: Text(l.tryAgain),
            ),
          ),
      ],
    );
  }
}
