// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'HomeMaps';

  @override
  String get from => 'From';

  @override
  String get to => 'To';

  @override
  String get via => 'Via';

  @override
  String get searchPlace => 'Search a place or address';

  @override
  String get addViaLabel => 'Add stop';

  @override
  String get swapEnds => 'Swap start and destination';

  @override
  String get removeLabel => 'Remove';

  @override
  String get clearRoute => 'Clear route';

  @override
  String get profileCar => 'Car';

  @override
  String get profileBike => 'Bike';

  @override
  String get profileWalk => 'Walk';

  @override
  String get options => 'Options';

  @override
  String get liveTraffic => 'Use live traffic';

  @override
  String get liveTrafficHelp => 'Current congestion and closures; car only';

  @override
  String get avoidMotorways => 'Avoid motorways';

  @override
  String get avoidTolls => 'Avoid toll roads';

  @override
  String get avoidFerries => 'Avoid ferries';

  @override
  String get routeCalculating => 'Calculating route…';

  @override
  String get noRoute => 'No route found between these points.';

  @override
  String get noRoadNearby =>
      'There is no road near one of the points that this mode of travel can use.';

  @override
  String get serverUnreachable => 'The server cannot be reached.';

  @override
  String get fastest => 'Fastest';

  @override
  String alternative(int number) {
    return 'Alternative $number';
  }

  @override
  String ascentDescent(int ascent, int descent) {
    return '+$ascent m / -$descent m';
  }

  @override
  String get withToll => 'toll';

  @override
  String get withFerry => 'ferry';

  @override
  String get instructions => 'Directions';

  @override
  String get elevationProfile => 'Elevation profile';

  @override
  String get directionsFrom => 'Directions from here';

  @override
  String get directionsTo => 'Directions to here';

  @override
  String get asStop => 'Add as stop';

  @override
  String get mapStyle => 'Map style';

  @override
  String get styleMap => 'Map';

  @override
  String get styleLight => 'Light';

  @override
  String get styleDark => 'Dark';

  @override
  String get themeAutomatic => 'Automatic';

  @override
  String get themeDay => 'Always day';

  @override
  String get themeNight => 'Always night';

  @override
  String get settings => 'Settings';

  @override
  String get server => 'Server';

  @override
  String get serverHelp =>
      'The address of your HomeMaps installation, for example https://maps.example.org';

  @override
  String get serverInvalid =>
      'Enter an address starting with http:// or https://.';

  @override
  String get save => 'Save';

  @override
  String get serverRequired => 'Set the address of your server first.';

  @override
  String get about => 'About';

  @override
  String get northUp => 'North up';

  @override
  String get searchHere => 'Search the map';

  @override
  String get route => 'Directions';

  @override
  String get backToSearch => 'Back to search';

  @override
  String get dragToReorder => 'Drag to reorder';

  @override
  String get trafficOnMap => 'Traffic';

  @override
  String get trafficRoadClosed => 'Road closed';

  @override
  String get trafficExitClosed => 'Exit closed';

  @override
  String get trafficOnRampClosed => 'On-ramp closed';

  @override
  String get trafficConnectingRoadClosed => 'Connecting road closed';

  @override
  String get trafficParallelRoadClosed => 'Parallel road closed';

  @override
  String get trafficCarriagewayClosed => 'Carriageway closed';

  @override
  String get trafficLaneClosed => 'Lane closed';

  @override
  String trafficLanesOpen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lanes open',
      one: '1 lane open',
    );
    return '$_temp0';
  }

  @override
  String get trafficJam => 'Traffic jam';

  @override
  String get trafficSlow => 'Slow traffic';

  @override
  String trafficDelay(String duration, int kmh) {
    return '+$duration delay · $kmh km/h';
  }

  @override
  String trafficUntil(String moment) {
    return 'Until $moment';
  }

  @override
  String get causeRoadworks => 'Roadworks';

  @override
  String get causeAccident => 'Accident';

  @override
  String get causeEvent => 'Event';

  @override
  String get myLocation => 'My location';

  @override
  String get locationDenied =>
      'Without permission the app can\'t show your location.';

  @override
  String get locationNever =>
      'Location is denied for HomeMaps. Turn it on in your phone\'s settings.';

  @override
  String get locationNeverWeb =>
      'Location is blocked for this site. Allow it via the padlock next to the address.';

  @override
  String get locationServiceOff => 'Location is turned off on your device.';

  @override
  String get locationNotFound =>
      'Your device can\'t determine your location; it keeps trying. Computers often can\'t, phones can.';

  @override
  String get startNavigation => 'Start';

  @override
  String navigationNotificationTitle(String destination) {
    return 'Navigating to $destination';
  }

  @override
  String get navigationNotificationText =>
      'HomeMaps is following your location for directions.';

  @override
  String get recalculating => 'Recalculating route.';

  @override
  String get recalculatingBusy => 'Recalculating…';

  @override
  String fasterRoute(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other:
          'There is a faster route, $minutes minutes faster. Choose on screen whether to take it.',
      one: 'There is a faster route, 1 minute faster. Choose on screen whether to take it.',
    );
    return '$_temp0';
  }

  @override
  String inDistance(String distance, String sentence) {
    return 'In $distance, $sentence';
  }

  @override
  String spokenMeters(int meter) {
    return '$meter meters';
  }

  @override
  String spokenKilometers(String km) {
    return '$km kilometers';
  }

  @override
  String get arrived => 'You have arrived';

  @override
  String get done => 'Done';

  @override
  String shortAction(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'onRamp': 'Take the ramp',
      'exit': 'Take the exit',
      'straight': 'Keep straight',
      'right': 'Keep right',
      'left': 'Keep left',
      'merge': 'Merge',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String exit(String number) {
    return 'Exit $number';
  }

  @override
  String lanesAhead(String distance, String perLane) {
    return 'In $distance: $perLane';
  }

  @override
  String lanesCorrect(int correct, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      correct,
      locale: localeName,
      other: '$correct correct lanes',
      one: '1 correct lane',
    );
    return '$_temp0 of $total';
  }

  @override
  String get resume => 'Re-centre';

  @override
  String get stopNavigation => 'Stop';

  @override
  String get voiceOff => 'Mute';

  @override
  String get voiceOn => 'Unmute';

  @override
  String arrival(String time) {
    return 'Arrive $time';
  }

  @override
  String get afterwards => 'Then';

  @override
  String get locationSearching => 'Finding location…';

  @override
  String get locationEnableToNavigate => 'Turn on location to navigate';

  @override
  String get navigatingWithoutLocation => 'Navigation needs your location.';

  @override
  String get tryAgain => 'Try again';

  @override
  String stopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'via $count stops',
      one: 'via 1 stop',
    );
    return '$_temp0';
  }

  @override
  String get editRoute => 'Edit route';

  @override
  String get stopFirst => 'Stop navigation first.';

  @override
  String get delay => 'delay';

  @override
  String suggestionFaster(int minutes) {
    return 'Faster route: $minutes min faster';
  }

  @override
  String suggestionVia(String road) {
    return 'via $road';
  }

  @override
  String get accept => 'Take it';

  @override
  String get ignore => 'Ignore';

  @override
  String arrivalAt(String time) {
    return 'arrive $time';
  }

  @override
  String get home => 'Home';

  @override
  String get work => 'Work';

  @override
  String get asHome => 'Set as home';

  @override
  String get asWork => 'Set as work';

  @override
  String get savedPlaces => 'Places';

  @override
  String get savedPlacesHelp =>
      'Set home and work on the card of a place you found.';

  @override
  String get notSet => 'Not set';

  @override
  String get recentPlaces => 'Recent places';

  @override
  String savedPlaceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count places',
      one: '1 place',
      zero: 'None',
    );
    return '$_temp0';
  }

  @override
  String get clearLabel => 'Clear';

  @override
  String notFound(String search) {
    return 'Not found: $search';
  }

  @override
  String get kmh => 'km/h';

  @override
  String speedLimit(int kmh) {
    return 'Speed limit $kmh km/h';
  }

  @override
  String speedLimitTemporary(int kmh) {
    return 'Temporary speed limit $kmh km/h';
  }

  @override
  String speedLimitMatrix(int kmh) {
    return 'Speed limit $kmh km/h on the overhead signs';
  }

  @override
  String get incidentAccident => 'Accident';

  @override
  String get incidentBreakdown => 'Broken-down vehicle';

  @override
  String get incidentObstacle => 'Object on the road';

  @override
  String get incidentBridge => 'Open bridge';

  @override
  String get matrixSigns => 'Overhead lane signs';

  @override
  String incidentSince(String time) {
    return 'Since $time';
  }

  @override
  String warningOnRoute(String notification, String distance) {
    return 'Caution: $notification in $distance.';
  }

  @override
  String get departure => 'Depart';

  @override
  String get departNow => 'Now';

  @override
  String get departLater => 'Later…';

  @override
  String closureOnRoute(String window, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count planned closures on this route, first: $window',
      one: 'Planned closure on this route: $window',
    );
    return '$_temp0';
  }

  @override
  String get alongTheRoute => 'Along the route';

  @override
  String get alongFuel => 'Fuel';

  @override
  String get alongCharging => 'Charging';

  @override
  String get alongSupermarket => 'Supermarket';

  @override
  String get alongFood => 'Food';

  @override
  String get alongNothing => 'Nothing found within a kilometre of the route.';

  @override
  String alongDistance(String distance) {
    return '$distance from the route';
  }

  @override
  String stopAdded(String label) {
    return 'Stop: $label';
  }

  @override
  String get locationSharing => 'Location sharing';

  @override
  String get locationSharingHelp =>
      'Send your position to your own server, like Colota does. Only while navigating.';

  @override
  String get locationSharingEnabled => 'Share while navigating';

  @override
  String get shareOff => 'Off';

  @override
  String get shareServer => 'Server';

  @override
  String get shareCustom => 'Custom server';

  @override
  String shareTemplateHelp(String template) {
    String _temp0 = intl.Intl.selectLogic(template, {
      'dawarich': 'Dawarich API: points in batches, with heading, battery and transport mode',
      'geopulse': 'Colota format for GeoPulse',
      'overland': 'Overland: points in batches (GeoJSON)',
      'owntracks': 'Standard OwnTracks HTTP format',
      'phonetrack': 'Nextcloud PhoneTrack',
      'reitti': 'OwnTracks-compatible format for Reitti',
      'traccar': 'Traccar, OsmAnd protocol',
      'other': 'Your own field names',
    });
    return '$_temp0';
  }

  @override
  String get shareUrl => 'Address (URL)';

  @override
  String get shareUrlInvalid =>
      'Enter an address starting with http:// or https://.';

  @override
  String get shareUrlWeb => 'In the browser the server must allow CORS.';

  @override
  String get shareMethod => 'Method';

  @override
  String get shareAuth => 'Authentication';

  @override
  String get shareAuthNone => 'None';

  @override
  String get shareUsername => 'Username';

  @override
  String get sharePassword => 'Password';

  @override
  String get shareToken => 'Token';

  @override
  String get shareFieldNames => 'Field names';

  @override
  String get shareFieldNamesHelp =>
      'One per line as field=name, e.g. lat=latitude. Fields: lat, lon, acc, alt, vel, tst, bear.';

  @override
  String get shareExtraFields => 'Fixed fields';

  @override
  String get shareExtraFieldsHelp =>
      'One per line as name=value; sent with every point.';

  @override
  String get shareInterval => 'Every … seconds';

  @override
  String get shareMinDistance => 'Or after … metres';

  @override
  String get shareTest => 'Test connection';

  @override
  String get shareTestSucceeded => 'The server received the point.';

  @override
  String shareTestFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get shareStatus => 'Status';

  @override
  String shareLastSent(String time) {
    return 'Last sent at $time';
  }

  @override
  String get shareNothingYet => 'Nothing sent yet';

  @override
  String shareQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points queued',
      one: '1 point queued',
      zero: 'Queue empty',
    );
    return '$_temp0';
  }

  @override
  String shareError(String error) {
    return 'Error: $error';
  }

  @override
  String get shareStopped => 'Stopped until you change the settings.';

  @override
  String get shareClearQueue => 'Clear queue';

  @override
  String get shareExample => 'Example';

  @override
  String get navigationNotificationSharing =>
      'HomeMaps follows your location for the route and shares it with your server.';

  @override
  String get aboutHomeMaps => 'About HomeMaps';

  @override
  String version(String version) {
    return 'Version $version';
  }

  @override
  String get aboutDescription =>
      'Navigation on your own server: map, routes, search and traffic.';

  @override
  String get sources => 'Data and software';

  @override
  String get sourceMapData => 'Map data © OpenStreetMap contributors';

  @override
  String get sourceTiles => 'Map tiles and style';

  @override
  String get sourceRouting => 'Routing and navigation';

  @override
  String get sourceSearch => 'Search';

  @override
  String get sourceTraffic => 'Traffic, roadworks and lane signals';

  @override
  String get sourceCode => 'Source code';

  @override
  String get licenses => 'Licenses';

  @override
  String get saveLog => 'Save log';

  @override
  String get saveLogSubtitle =>
      'Save the app log to a file for troubleshooting';

  @override
  String get logSaved => 'Log saved';

  @override
  String logSaveFailed(String error) {
    return 'Could not save the log: $error';
  }

  @override
  String get logEmpty => 'There is no log to save yet';

  @override
  String get dawarich => 'Dawarich';

  @override
  String get dawarichHelp =>
      'Enter the address of your own Dawarich. Then sign in, and you can share your location with your family, record your trips while navigating and see family members on the map.';

  @override
  String get dawarichNotSignedIn => 'Not signed in';

  @override
  String get dawarichServer => 'Server';

  @override
  String get dawarichWithKey => 'With an API key';

  @override
  String get dawarichEmail => 'Email';

  @override
  String get dawarichPassword => 'Password';

  @override
  String get dawarichKey => 'API key';

  @override
  String get dawarichKeyHelp => 'Found in Dawarich under Settings.';

  @override
  String get dawarichSignIn => 'Sign in';

  @override
  String get dawarichSignOut => 'Sign out';

  @override
  String get dawarichCode => 'Two-factor code';

  @override
  String get dawarichCodeHelp =>
      'The code from your authenticator app, or a backup code.';

  @override
  String get dawarichConfirm => 'Confirm';

  @override
  String get cancelLabel => 'Cancel';

  @override
  String get dawarichErrorCredentials => 'Incorrect credentials.';

  @override
  String get dawarichErrorPasswordDisabled =>
      'This server does not allow signing in with a password. Use an API key.';

  @override
  String get dawarichErrorBlocked => 'Too many wrong codes. Try again later.';

  @override
  String dawarichErrorConnection(String detail) {
    return 'Cannot reach Dawarich ($detail).';
  }

  @override
  String dawarichErrorUnknown(String detail) {
    return 'Something went wrong ($detail).';
  }

  @override
  String dawarichSignedInAs(String email) {
    return 'Signed in as $email';
  }

  @override
  String get dawarichFamily => 'Family';

  @override
  String get dawarichShareWithFamily => 'Share location with family';

  @override
  String dawarichSharingUntil(String time) {
    return 'Until $time';
  }

  @override
  String get dawarichSharingAlways => 'Until you turn it off';

  @override
  String get dawarichNotSharing => 'Your family can\'t see your location';

  @override
  String get dawarichNoFamily =>
      'You\'re not in a family yet. Create or join one on the Dawarich website.';

  @override
  String get dawarichOpenWebsite => 'Open website';

  @override
  String get dawarichNoSubscription =>
      'Family is not included in your Dawarich plan.';

  @override
  String get dawarichHowLong => 'Share for how long?';

  @override
  String dawarichDuration(String duration) {
    String _temp0 = intl.Intl.selectLogic(duration, {
      'hour1': '1 hour',
      'hour6': '6 hours',
      'hour12': '12 hours',
      'hour24': '24 hours',
      'other': 'Until I turn it off',
    });
    return '$_temp0';
  }

  @override
  String get dawarichShareEnRoute => 'Share location while navigating';

  @override
  String get dawarichShareEnRouteHelp =>
      'Sends your trip to Dawarich. Set interval and distance under Location sharing.';

  @override
  String get dawarichShowFamily => 'Family members on the map';

  @override
  String get dawarichShowFamilyHelp =>
      'Updated every 30 seconds while the app is open.';

  @override
  String get dawarichFamilySharing => 'family sharing';

  @override
  String get shareViaDawarich => 'Set up through your Dawarich account.';

  @override
  String familyMinutesAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes ago',
      one: '1 minute ago',
      zero: 'just now',
    );
    return '$_temp0';
  }

  @override
  String familyBattery(int percent) {
    return 'battery $percent%';
  }

  @override
  String familyHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String familyDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get familyFollow => 'Follow';

  @override
  String get familyFollowing => 'Following';

  @override
  String get settingsGroupMap => 'Map and route';

  @override
  String get settingsGroupSharing => 'Sharing';

  @override
  String get settingsGroupApp => 'App';

  @override
  String get settingsMap => 'Map';

  @override
  String get dayAndNight => 'Day and night';

  @override
  String get themeOnlyMap =>
      'Only for the Map style; Light and Dark are already a choice.';

  @override
  String get layers => 'Layers';

  @override
  String get trafficOnMapHelp =>
      'Closures, road works and traffic jams on the map';

  @override
  String get transport => 'Transport';

  @override
  String get transportHelp => 'Used to calculate a new route.';

  @override
  String get saved => 'Saved';

  @override
  String get aboutSummary => 'Version, sources and licenses';

  @override
  String get dawarichAccount => 'Account';

  @override
  String get dawarichNavigation => 'Navigation';

  @override
  String get shareConnection => 'Connection';

  @override
  String get sharePoints => 'Points';

  @override
  String get dawarichWebsiteHelp =>
      'Also for OIDC, such as Keycloak or Authentik. Not with Google.';

  @override
  String get dawarichWebsiteSignIn => 'Via the Dawarich website';

  @override
  String get dawarichWebsiteTitle => 'Sign in to Dawarich';

  @override
  String dawarichWebsiteError(String error) {
    return 'The page does not load: $error';
  }

  @override
  String get dawarichErrorCors =>
      'Dawarich cannot be reached from the browser. Dawarich does not allow this itself (CORS); add CORS headers for /api/v1 in your reverse proxy, or use the Android app.';

  @override
  String get dawarichErrorNotDawarich =>
      'No Dawarich answers at this address. If a login proxy (such as Authelia) is in front of it, let /api/v1 through.';

  @override
  String get dawarichStepServer => 'Server';

  @override
  String get dawarichConnect => 'Connect';

  @override
  String get dawarichConnected => 'Connected';

  @override
  String dawarichConnectedVersion(String version) {
    return 'Connected · Dawarich $version';
  }

  @override
  String get dawarichChange => 'Change';

  @override
  String get dawarichStepSignIn => 'Sign in';

  @override
  String get dawarichOtherWays => 'Other ways';

  @override
  String get dawarichSignOutQuestion => 'Sign out of Dawarich?';

  @override
  String get dawarichSignOutHelp =>
      'Sharing while navigating stops, and your family disappears from the map.';

  @override
  String get dawarichChecking => 'Checking connection…';

  @override
  String get dawarichSessionExpired => 'Session expired';

  @override
  String get dawarichSessionExpiredHelp =>
      'Your API key no longer works. Sign in again.';

  @override
  String get dawarichUnreachable => 'Not reachable';

  @override
  String get dawarichSignInAgain => 'Sign in again';

  @override
  String get carWhereTo => 'Where to?';

  @override
  String get carOpenApp => 'Open HomeMaps on your phone and turn on location.';

  @override
  String get carNoResults => 'Nothing found.';

  @override
  String get carRoutes => 'Routes';
}
