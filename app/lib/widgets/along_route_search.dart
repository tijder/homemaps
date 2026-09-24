import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../l10n/app_localizations.dart';
import '../models/place.dart';
import '../providers/services.dart';
import '../providers/settings.dart';
import '../services/along_route.dart';
import '../utils/formatting.dart';

/// "Along the route": fuel, charging, supermarket, food. Choosing a category
/// searches the own map tiles and shows the stops with their detour; choosing
/// a stop adds it as a waypoint.
class AlongRouteSearch extends ConsumerStatefulWidget {
  const AlongRouteSearch({
    super.key,
    required this.line,
    required this.onChosen,
  });

  /// The route from where you are now (or from the start).
  final List<LatLng> line;
  final ValueChanged<Place> onChosen;

  @override
  ConsumerState<AlongRouteSearch> createState() => _AlongRouteSearchState();
}

class _AlongRouteSearchState extends ConsumerState<AlongRouteSearch> {
  PoiCategory? _category;
  Future<List<AlongRouteHit>>? _hits;

  static String _label(AppLocalizations l, PoiCategory c) => switch (c) {
    PoiCategory.fuel => l.alongFuel,
    PoiCategory.charging => l.alongCharging,
    PoiCategory.supermarket => l.alongSupermarket,
    PoiCategory.food => l.alongFood,
  };

  static IconData _iconFor(PoiCategory c) => switch (c) {
    PoiCategory.fuel => Icons.local_gas_station,
    PoiCategory.charging => Icons.ev_station,
    PoiCategory.supermarket => Icons.local_grocery_store,
    PoiCategory.food => Icons.restaurant,
  };

  void _choose(PoiCategory category) {
    final l = AppLocalizations.of(context);
    final service = ref.read(alongRouteProvider);
    setState(() {
      if (_category == category) {
        _category = null;
        _hits = null;
        return;
      }
      _category = category;
      _hits = service?.search(
        widget.line,
        category,
        profile: ref.read(settingsProvider).profile,
        unnamedLabel: _label(l, category),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.alongTheRoute, style: text.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final c in PoiCategory.values)
              FilterChip(
                avatar: Icon(_iconFor(c), size: 18),
                label: Text(_label(l, c)),
                selected: _category == c,
                showCheckmark: false,
                onSelected: (_) => _choose(c),
              ),
          ],
        ),
        if (_hits case final hits?)
          FutureBuilder<List<AlongRouteHit>>(
            future: hits,
            builder: (context, status) {
              if (status.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final list = status.data ?? const [];
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(l.alongNothing, style: text.bodyMedium),
                );
              }
              return Column(
                children: [
                  for (final t in list.take(8))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_iconFor(_category!)),
                      title: Text(
                        t.place.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        l.alongDistance(
                          distance(t.distanceToRoute, l.localeName),
                        ),
                      ),
                      trailing: t.detourSeconds == null
                          ? null
                          : Text(
                              '+${duration(t.detourSeconds!)}',
                              style: text.titleSmall,
                            ),
                      onTap: () => widget.onChosen(t.place),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}
