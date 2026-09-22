import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../utils/opmaak.dart';

/// Wat er aan de hand is op een aangetikt stuk van de verkeerslaag. De
/// eigenschappen komen van de importer: codes uit NDW's feed, hier vertaald.
class VerkeerMelding extends StatelessWidget {
  const VerkeerMelding(this.eigenschappen, {super.key});

  final Map<String, dynamic> eigenschappen;

  /// Titel en de regels eronder; los van [build] zodat het te testen is.
  static (String, List<String>) tekst(
    AppLocalizations l,
    String taal,
    Map<String, dynamic> info,
  ) {
    final soort = info['soort'];
    final regels = <String>[];
    if (soort case 'ongeval' || 'pech' || 'obstakel') {
      final sinds = DateTime.tryParse(info['sinds'] as String? ?? '');
      if (sinds != null) {
        regels.add(l.meldingSinds(DateFormat.Hm(taal).format(sinds.toLocal())));
      }
      return (
        switch (soort) {
          'ongeval' => l.meldingOngeval,
          'pech' => l.meldingPech,
          _ => l.meldingObstakel,
        },
        regels,
      );
    }
    if (soort == 'file' || soort == 'traag') {
      final vertraging = (info['vertraging_s'] as num?)?.toDouble() ?? 0;
      regels.add(
        l.verkeerVertraging(
          duur(vertraging),
          (info['kmu'] as num?)?.toInt() ?? 0,
        ),
      );
      return (soort == 'file' ? l.verkeerFile : l.verkeerTraag, regels);
    }
    final titel = soort == 'werk'
        ? l.verkeerRijstrookDicht
        : info['hele_weg'] == true
        ? l.verkeerWegDicht
        : switch (info['rijbaan']) {
            'exitSlipRoad' => l.verkeerAfritDicht,
            'entrySlipRoad' => l.verkeerOpritDicht,
            'connectingCarriageway' => l.verkeerVerbindingswegDicht,
            'parallelCarriageway' => l.verkeerParallelbaanDicht,
            _ => l.verkeerRijbaanDicht,
          };
    final open = (info['stroken_open'] as num?)?.toInt();
    if (soort == 'werk' && open != null && open > 0) {
      regels.add(l.verkeerStrokenOpen(open));
    }
    final oorzaak = switch (info['oorzaak']) {
      'roadMaintenance' || 'constructionWork' => l.oorzaakWerk,
      'accident' => l.oorzaakOngeval,
      'publicEvent' => l.oorzaakEvenement,
      _ => null,
    };
    if (oorzaak != null) regels.add(oorzaak);
    final tot = DateTime.tryParse(info['tot'] as String? ?? '');
    if (tot != null) {
      regels.add(
        l.verkeerTot(DateFormat('EEE d MMM HH:mm', taal).format(tot.toLocal())),
      );
    }
    return (titel, regels);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final taal = Localizations.localeOf(context).languageCode;
    final (titel, regels) = tekst(l, taal, eigenschappen);
    final thema = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titel, style: thema.titleMedium),
          for (final regel in regels) ...[
            const SizedBox(height: 4),
            Text(regel, style: thema.bodyMedium),
          ],
        ],
      ),
    );
  }
}
