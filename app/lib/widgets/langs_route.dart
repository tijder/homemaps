import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../l10n/app_localizations.dart';
import '../models/plaats.dart';
import '../providers/diensten.dart';
import '../providers/instellingen.dart';
import '../services/langs_route.dart';
import '../utils/opmaak.dart';

/// "Langs de route": tanken, laden, supermarkt, eten. Een categorie kiezen
/// zoekt in de eigen kaarttegels en toont de stops met hun omweg; een stop
/// kiezen voegt hem toe als tussenpunt.
class LangsRouteZoeker extends ConsumerStatefulWidget {
  const LangsRouteZoeker({
    super.key,
    required this.lijn,
    required this.onGekozen,
  });

  /// De route vanaf waar je nu bent (of vanaf het begin).
  final List<LatLng> lijn;
  final ValueChanged<Plaats> onGekozen;

  @override
  ConsumerState<LangsRouteZoeker> createState() => _LangsRouteZoekerState();
}

class _LangsRouteZoekerState extends ConsumerState<LangsRouteZoeker> {
  Categorie? _categorie;
  Future<List<Treffer>>? _treffers;

  static String _naam(AppLocalizations l, Categorie c) => switch (c) {
    Categorie.tanken => l.langsTanken,
    Categorie.laden => l.langsLaden,
    Categorie.supermarkt => l.langsSupermarkt,
    Categorie.eten => l.langsEten,
  };

  static IconData _pictogram(Categorie c) => switch (c) {
    Categorie.tanken => Icons.local_gas_station,
    Categorie.laden => Icons.ev_station,
    Categorie.supermarkt => Icons.local_grocery_store,
    Categorie.eten => Icons.restaurant,
  };

  void _kies(Categorie categorie) {
    final l = AppLocalizations.of(context);
    final dienst = ref.read(langsRouteProvider);
    setState(() {
      if (_categorie == categorie) {
        _categorie = null;
        _treffers = null;
        return;
      }
      _categorie = categorie;
      _treffers = dienst?.zoek(
        widget.lijn,
        categorie,
        profiel: ref.read(instellingenProvider).profiel,
        naamZonderNaam: _naam(l, categorie),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tekst = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.langsDeRoute, style: tekst.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final c in Categorie.values)
              FilterChip(
                avatar: Icon(_pictogram(c), size: 18),
                label: Text(_naam(l, c)),
                selected: _categorie == c,
                showCheckmark: false,
                onSelected: (_) => _kies(c),
              ),
          ],
        ),
        if (_treffers case final treffers?)
          FutureBuilder<List<Treffer>>(
            future: treffers,
            builder: (context, stand) {
              if (stand.connectionState != ConnectionState.done) {
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
              final lijst = stand.data ?? const [];
              if (lijst.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(l.langsNiets, style: tekst.bodyMedium),
                );
              }
              return Column(
                children: [
                  for (final t in lijst.take(8))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_pictogram(_categorie!)),
                      title: Text(
                        t.plaats.naam,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        l.langsAfstand(
                          afstand(t.afstandTotRoute, l.localeName),
                        ),
                      ),
                      trailing: t.omwegSeconden == null
                          ? null
                          : Text(
                              '+${duur(t.omwegSeconden!)}',
                              style: tekst.titleSmall,
                            ),
                      onTap: () => widget.onGekozen(t.plaats),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}
