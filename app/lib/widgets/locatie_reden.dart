import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';
import '../providers/locatie.dart';

/// Waarom er geen locatie is, in woorden voor de gebruiker; null als er niets
/// mis is (aan, of nog niet gevraagd).
String? locatieReden(AppLocalizations l, LocatieStand stand) => switch (stand) {
  LocatieStand.permanentGeweigerd =>
    kIsWeb ? l.locatieNooitWeb : l.locatieNooit,
  LocatieStand.dienstUit => l.locatieDienstUit,
  LocatieStand.geweigerd => l.locatieGeweigerd,
  LocatieStand.nietGevonden => l.locatieNietGevonden,
  LocatieStand.zoekt || LocatieStand.aan || LocatieStand.uit => null,
};
