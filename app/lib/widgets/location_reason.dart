import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';
import '../providers/location.dart';

/// Why there is no location, in words for the user; null if nothing is wrong
/// (on, or not asked yet).
String? locationReason(AppLocalizations l, LocationStatus status) =>
    switch (status) {
      LocationStatus.permanentlyDenied =>
        kIsWeb ? l.locationNeverWeb : l.locationNever,
      LocationStatus.serviceOff => l.locationServiceOff,
      LocationStatus.denied => l.locationDenied,
      LocationStatus.notFound => l.locationNotFound,
      LocationStatus.searching ||
      LocationStatus.enabled ||
      LocationStatus.off => null,
    };
