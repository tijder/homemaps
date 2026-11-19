import '../l10n/app_localizations.dart';

/// What distances and speeds are shown and spoken in.
enum Units {
  metric,
  imperial;

  String label(AppLocalizations l) => switch (this) {
    metric => l.unitsMetric,
    imperial => l.unitsImperial,
  };
}
