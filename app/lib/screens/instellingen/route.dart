import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/route_opties.dart';
import 'sectie.dart';

/// Het vervoer en de route-opties; dezelfde als in het routepaneel.
class RouteInstellingen extends StatelessWidget {
  const RouteInstellingen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return InstellingenLijst(
      children: [
        InstellingenSectie(
          titel: l.vervoer,
          uitleg: l.vervoerUitleg,
          children: const [SectieBlok(child: ProfielKeuze())],
        ),
        InstellingenSectie(titel: l.opties, children: const [RouteOpties()]),
      ],
    );
  }
}
