import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_nl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('nl'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'HomeMaps'**
  String get appTitle;

  /// No description provided for @from.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get from;

  /// No description provided for @to.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get to;

  /// No description provided for @via.
  ///
  /// In en, this message translates to:
  /// **'Via'**
  String get via;

  /// No description provided for @searchPlace.
  ///
  /// In en, this message translates to:
  /// **'Search a place or address'**
  String get searchPlace;

  /// No description provided for @addViaLabel.
  ///
  /// In en, this message translates to:
  /// **'Add stop'**
  String get addViaLabel;

  /// No description provided for @swapEnds.
  ///
  /// In en, this message translates to:
  /// **'Swap start and destination'**
  String get swapEnds;

  /// No description provided for @removeLabel.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeLabel;

  /// No description provided for @clearRoute.
  ///
  /// In en, this message translates to:
  /// **'Clear route'**
  String get clearRoute;

  /// No description provided for @profileCar.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get profileCar;

  /// No description provided for @profileBike.
  ///
  /// In en, this message translates to:
  /// **'Bike'**
  String get profileBike;

  /// No description provided for @profileWalk.
  ///
  /// In en, this message translates to:
  /// **'Walk'**
  String get profileWalk;

  /// No description provided for @options.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get options;

  /// No description provided for @liveTraffic.
  ///
  /// In en, this message translates to:
  /// **'Use live traffic'**
  String get liveTraffic;

  /// No description provided for @liveTrafficHelp.
  ///
  /// In en, this message translates to:
  /// **'Current congestion and closures; car only'**
  String get liveTrafficHelp;

  /// No description provided for @avoidMotorways.
  ///
  /// In en, this message translates to:
  /// **'Avoid motorways'**
  String get avoidMotorways;

  /// No description provided for @avoidTolls.
  ///
  /// In en, this message translates to:
  /// **'Avoid toll roads'**
  String get avoidTolls;

  /// No description provided for @avoidFerries.
  ///
  /// In en, this message translates to:
  /// **'Avoid ferries'**
  String get avoidFerries;

  /// No description provided for @routeCalculating.
  ///
  /// In en, this message translates to:
  /// **'Calculating route…'**
  String get routeCalculating;

  /// No description provided for @noRoute.
  ///
  /// In en, this message translates to:
  /// **'No route found between these points.'**
  String get noRoute;

  /// No description provided for @noRoadNearby.
  ///
  /// In en, this message translates to:
  /// **'There is no road near one of the points that this mode of travel can use.'**
  String get noRoadNearby;

  /// No description provided for @serverUnreachable.
  ///
  /// In en, this message translates to:
  /// **'The server cannot be reached.'**
  String get serverUnreachable;

  /// No description provided for @fastest.
  ///
  /// In en, this message translates to:
  /// **'Fastest'**
  String get fastest;

  /// No description provided for @alternative.
  ///
  /// In en, this message translates to:
  /// **'Alternative {number}'**
  String alternative(int number);

  /// No description provided for @ascentDescent.
  ///
  /// In en, this message translates to:
  /// **'+{ascent} m / -{descent} m'**
  String ascentDescent(int ascent, int descent);

  /// No description provided for @withToll.
  ///
  /// In en, this message translates to:
  /// **'toll'**
  String get withToll;

  /// No description provided for @withFerry.
  ///
  /// In en, this message translates to:
  /// **'ferry'**
  String get withFerry;

  /// No description provided for @instructions.
  ///
  /// In en, this message translates to:
  /// **'Directions'**
  String get instructions;

  /// No description provided for @elevationProfile.
  ///
  /// In en, this message translates to:
  /// **'Elevation profile'**
  String get elevationProfile;

  /// No description provided for @directionsFrom.
  ///
  /// In en, this message translates to:
  /// **'Directions from here'**
  String get directionsFrom;

  /// No description provided for @directionsTo.
  ///
  /// In en, this message translates to:
  /// **'Directions to here'**
  String get directionsTo;

  /// No description provided for @asStop.
  ///
  /// In en, this message translates to:
  /// **'Add as stop'**
  String get asStop;

  /// No description provided for @mapStyle.
  ///
  /// In en, this message translates to:
  /// **'Map style'**
  String get mapStyle;

  /// No description provided for @styleMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get styleMap;

  /// No description provided for @styleLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get styleLight;

  /// No description provided for @styleDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get styleDark;

  /// No description provided for @themeAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get themeAutomatic;

  /// No description provided for @themeDay.
  ///
  /// In en, this message translates to:
  /// **'Always day'**
  String get themeDay;

  /// No description provided for @themeNight.
  ///
  /// In en, this message translates to:
  /// **'Always night'**
  String get themeNight;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @server.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get server;

  /// No description provided for @serverHelp.
  ///
  /// In en, this message translates to:
  /// **'The address of your HomeMaps installation, for example https://maps.example.org'**
  String get serverHelp;

  /// No description provided for @serverInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter an address starting with http:// or https://.'**
  String get serverInvalid;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @serverRequired.
  ///
  /// In en, this message translates to:
  /// **'Set the address of your server first.'**
  String get serverRequired;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @northUp.
  ///
  /// In en, this message translates to:
  /// **'North up'**
  String get northUp;

  /// No description provided for @searchHere.
  ///
  /// In en, this message translates to:
  /// **'Search the map'**
  String get searchHere;

  /// No description provided for @route.
  ///
  /// In en, this message translates to:
  /// **'Directions'**
  String get route;

  /// No description provided for @backToSearch.
  ///
  /// In en, this message translates to:
  /// **'Back to search'**
  String get backToSearch;

  /// No description provided for @dragToReorder.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get dragToReorder;

  /// No description provided for @trafficOnMap.
  ///
  /// In en, this message translates to:
  /// **'Traffic'**
  String get trafficOnMap;

  /// No description provided for @trafficRoadClosed.
  ///
  /// In en, this message translates to:
  /// **'Road closed'**
  String get trafficRoadClosed;

  /// No description provided for @trafficExitClosed.
  ///
  /// In en, this message translates to:
  /// **'Exit closed'**
  String get trafficExitClosed;

  /// No description provided for @trafficOnRampClosed.
  ///
  /// In en, this message translates to:
  /// **'On-ramp closed'**
  String get trafficOnRampClosed;

  /// No description provided for @trafficConnectingRoadClosed.
  ///
  /// In en, this message translates to:
  /// **'Connecting road closed'**
  String get trafficConnectingRoadClosed;

  /// No description provided for @trafficParallelRoadClosed.
  ///
  /// In en, this message translates to:
  /// **'Parallel road closed'**
  String get trafficParallelRoadClosed;

  /// No description provided for @trafficCarriagewayClosed.
  ///
  /// In en, this message translates to:
  /// **'Carriageway closed'**
  String get trafficCarriagewayClosed;

  /// No description provided for @trafficLaneClosed.
  ///
  /// In en, this message translates to:
  /// **'Lane closed'**
  String get trafficLaneClosed;

  /// No description provided for @trafficLanesOpen.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 lane open} other{{count} lanes open}}'**
  String trafficLanesOpen(int count);

  /// No description provided for @trafficJam.
  ///
  /// In en, this message translates to:
  /// **'Traffic jam'**
  String get trafficJam;

  /// No description provided for @trafficSlow.
  ///
  /// In en, this message translates to:
  /// **'Slow traffic'**
  String get trafficSlow;

  /// No description provided for @trafficDelay.
  ///
  /// In en, this message translates to:
  /// **'+{duration} delay · {kmh} km/h'**
  String trafficDelay(String duration, int kmh);

  /// No description provided for @trafficUntil.
  ///
  /// In en, this message translates to:
  /// **'Until {moment}'**
  String trafficUntil(String moment);

  /// No description provided for @causeRoadworks.
  ///
  /// In en, this message translates to:
  /// **'Roadworks'**
  String get causeRoadworks;

  /// No description provided for @causeAccident.
  ///
  /// In en, this message translates to:
  /// **'Accident'**
  String get causeAccident;

  /// No description provided for @causeEvent.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get causeEvent;

  /// No description provided for @myLocation.
  ///
  /// In en, this message translates to:
  /// **'My location'**
  String get myLocation;

  /// No description provided for @locationDenied.
  ///
  /// In en, this message translates to:
  /// **'Without permission the app can\'t show your location.'**
  String get locationDenied;

  /// No description provided for @locationNever.
  ///
  /// In en, this message translates to:
  /// **'Location is denied for HomeMaps. Turn it on in your phone\'s settings.'**
  String get locationNever;

  /// No description provided for @locationNeverWeb.
  ///
  /// In en, this message translates to:
  /// **'Location is blocked for this site. Allow it via the padlock next to the address.'**
  String get locationNeverWeb;

  /// No description provided for @locationServiceOff.
  ///
  /// In en, this message translates to:
  /// **'Location is turned off on your device.'**
  String get locationServiceOff;

  /// No description provided for @locationNotFound.
  ///
  /// In en, this message translates to:
  /// **'Your device can\'t determine your location; it keeps trying. Computers often can\'t, phones can.'**
  String get locationNotFound;

  /// No description provided for @startNavigation.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get startNavigation;

  /// No description provided for @navigationNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Navigating to {destination}'**
  String navigationNotificationTitle(String destination);

  /// No description provided for @navigationNotificationText.
  ///
  /// In en, this message translates to:
  /// **'HomeMaps is following your location for directions.'**
  String get navigationNotificationText;

  /// No description provided for @recalculating.
  ///
  /// In en, this message translates to:
  /// **'Recalculating route.'**
  String get recalculating;

  /// No description provided for @recalculatingBusy.
  ///
  /// In en, this message translates to:
  /// **'Recalculating…'**
  String get recalculatingBusy;

  /// No description provided for @fasterRoute.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{There is a faster route, 1 minute faster. Choose on screen whether to take it.} other{There is a faster route, {minutes} minutes faster. Choose on screen whether to take it.}}'**
  String fasterRoute(int minutes);

  /// No description provided for @inDistance.
  ///
  /// In en, this message translates to:
  /// **'In {distance}, {sentence}'**
  String inDistance(String distance, String sentence);

  /// No description provided for @spokenMeters.
  ///
  /// In en, this message translates to:
  /// **'{meter} meters'**
  String spokenMeters(int meter);

  /// No description provided for @spokenKilometers.
  ///
  /// In en, this message translates to:
  /// **'{km} kilometers'**
  String spokenKilometers(String km);

  /// No description provided for @arrived.
  ///
  /// In en, this message translates to:
  /// **'You have arrived'**
  String get arrived;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// What you do at an on- or off-ramp, fork or merge lane, short, in the navigation header.
  ///
  /// In en, this message translates to:
  /// **'{kind, select, onRamp{Take the ramp} exit{Take the exit} straight{Keep straight} right{Keep right} left{Keep left} merge{Merge} other{}}'**
  String shortAction(String kind);

  /// No description provided for @exit.
  ///
  /// In en, this message translates to:
  /// **'Exit {number}'**
  String exit(String number);

  /// No description provided for @lanesAhead.
  ///
  /// In en, this message translates to:
  /// **'In {distance}: {perLane}'**
  String lanesAhead(String distance, String perLane);

  /// No description provided for @lanesCorrect.
  ///
  /// In en, this message translates to:
  /// **'{correct, plural, =1{1 correct lane} other{{correct} correct lanes}} of {total}'**
  String lanesCorrect(int correct, int total);

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Re-centre'**
  String get resume;

  /// No description provided for @stopNavigation.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopNavigation;

  /// No description provided for @voiceOff.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get voiceOff;

  /// No description provided for @voiceOn.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get voiceOn;

  /// No description provided for @arrival.
  ///
  /// In en, this message translates to:
  /// **'Arrive {time}'**
  String arrival(String time);

  /// No description provided for @afterwards.
  ///
  /// In en, this message translates to:
  /// **'Then'**
  String get afterwards;

  /// No description provided for @locationSearching.
  ///
  /// In en, this message translates to:
  /// **'Finding location…'**
  String get locationSearching;

  /// No description provided for @locationEnableToNavigate.
  ///
  /// In en, this message translates to:
  /// **'Turn on location to navigate'**
  String get locationEnableToNavigate;

  /// No description provided for @navigatingWithoutLocation.
  ///
  /// In en, this message translates to:
  /// **'Navigation needs your location.'**
  String get navigatingWithoutLocation;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @stopCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{via 1 stop} other{via {count} stops}}'**
  String stopCount(int count);

  /// No description provided for @editRoute.
  ///
  /// In en, this message translates to:
  /// **'Edit route'**
  String get editRoute;

  /// No description provided for @stopFirst.
  ///
  /// In en, this message translates to:
  /// **'Stop navigation first.'**
  String get stopFirst;

  /// No description provided for @delay.
  ///
  /// In en, this message translates to:
  /// **'delay'**
  String get delay;

  /// No description provided for @suggestionFaster.
  ///
  /// In en, this message translates to:
  /// **'Faster route: {minutes} min faster'**
  String suggestionFaster(int minutes);

  /// No description provided for @suggestionVia.
  ///
  /// In en, this message translates to:
  /// **'via {road}'**
  String suggestionVia(String road);

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Take it'**
  String get accept;

  /// No description provided for @ignore.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get ignore;

  /// No description provided for @arrivalAt.
  ///
  /// In en, this message translates to:
  /// **'arrive {time}'**
  String arrivalAt(String time);

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @work.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get work;

  /// No description provided for @asHome.
  ///
  /// In en, this message translates to:
  /// **'Set as home'**
  String get asHome;

  /// No description provided for @asWork.
  ///
  /// In en, this message translates to:
  /// **'Set as work'**
  String get asWork;

  /// No description provided for @savedPlaces.
  ///
  /// In en, this message translates to:
  /// **'Places'**
  String get savedPlaces;

  /// No description provided for @savedPlacesHelp.
  ///
  /// In en, this message translates to:
  /// **'Set home and work on the card of a place you found.'**
  String get savedPlacesHelp;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @recentPlaces.
  ///
  /// In en, this message translates to:
  /// **'Recent places'**
  String get recentPlaces;

  /// No description provided for @savedPlaceCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{None} =1{1 place} other{{count} places}}'**
  String savedPlaceCount(int count);

  /// No description provided for @clearLabel.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearLabel;

  /// No description provided for @notFound.
  ///
  /// In en, this message translates to:
  /// **'Not found: {search}'**
  String notFound(String search);

  /// No description provided for @kmh.
  ///
  /// In en, this message translates to:
  /// **'km/h'**
  String get kmh;

  /// No description provided for @speedLimit.
  ///
  /// In en, this message translates to:
  /// **'Speed limit {kmh} km/h'**
  String speedLimit(int kmh);

  /// No description provided for @speedLimitTemporary.
  ///
  /// In en, this message translates to:
  /// **'Temporary speed limit {kmh} km/h'**
  String speedLimitTemporary(int kmh);

  /// No description provided for @speedLimitMatrix.
  ///
  /// In en, this message translates to:
  /// **'Speed limit {kmh} km/h on the overhead signs'**
  String speedLimitMatrix(int kmh);

  /// No description provided for @incidentAccident.
  ///
  /// In en, this message translates to:
  /// **'Accident'**
  String get incidentAccident;

  /// No description provided for @incidentBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Broken-down vehicle'**
  String get incidentBreakdown;

  /// No description provided for @incidentObstacle.
  ///
  /// In en, this message translates to:
  /// **'Object on the road'**
  String get incidentObstacle;

  /// No description provided for @incidentBridge.
  ///
  /// In en, this message translates to:
  /// **'Open bridge'**
  String get incidentBridge;

  /// No description provided for @matrixSigns.
  ///
  /// In en, this message translates to:
  /// **'Overhead lane signs'**
  String get matrixSigns;

  /// No description provided for @incidentSince.
  ///
  /// In en, this message translates to:
  /// **'Since {time}'**
  String incidentSince(String time);

  /// No description provided for @warningOnRoute.
  ///
  /// In en, this message translates to:
  /// **'Caution: {notification} in {distance}.'**
  String warningOnRoute(String notification, String distance);

  /// No description provided for @departure.
  ///
  /// In en, this message translates to:
  /// **'Depart'**
  String get departure;

  /// No description provided for @departNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get departNow;

  /// No description provided for @departLater.
  ///
  /// In en, this message translates to:
  /// **'Later…'**
  String get departLater;

  /// No description provided for @closureOnRoute.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Planned closure on this route: {window}} other{{count} planned closures on this route, first: {window}}}'**
  String closureOnRoute(String window, int count);

  /// No description provided for @alongTheRoute.
  ///
  /// In en, this message translates to:
  /// **'Along the route'**
  String get alongTheRoute;

  /// No description provided for @alongFuel.
  ///
  /// In en, this message translates to:
  /// **'Fuel'**
  String get alongFuel;

  /// No description provided for @alongCharging.
  ///
  /// In en, this message translates to:
  /// **'Charging'**
  String get alongCharging;

  /// No description provided for @alongSupermarket.
  ///
  /// In en, this message translates to:
  /// **'Supermarket'**
  String get alongSupermarket;

  /// No description provided for @alongFood.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get alongFood;

  /// No description provided for @alongNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing found within a kilometre of the route.'**
  String get alongNothing;

  /// No description provided for @alongDistance.
  ///
  /// In en, this message translates to:
  /// **'{distance} from the route'**
  String alongDistance(String distance);

  /// No description provided for @stopAdded.
  ///
  /// In en, this message translates to:
  /// **'Stop: {label}'**
  String stopAdded(String label);

  /// No description provided for @locationSharing.
  ///
  /// In en, this message translates to:
  /// **'Location sharing'**
  String get locationSharing;

  /// No description provided for @locationSharingHelp.
  ///
  /// In en, this message translates to:
  /// **'Send your position to your own server, like Colota does. Only while navigating.'**
  String get locationSharingHelp;

  /// No description provided for @locationSharingEnabled.
  ///
  /// In en, this message translates to:
  /// **'Share while navigating'**
  String get locationSharingEnabled;

  /// No description provided for @shareOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get shareOff;

  /// No description provided for @shareServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get shareServer;

  /// No description provided for @shareCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom server'**
  String get shareCustom;

  /// No description provided for @shareTemplateHelp.
  ///
  /// In en, this message translates to:
  /// **'{template, select, dawarich{Dawarich API: points in batches, with heading, battery and transport mode} geopulse{Colota format for GeoPulse} overland{Overland: points in batches (GeoJSON)} owntracks{Standard OwnTracks HTTP format} phonetrack{Nextcloud PhoneTrack} reitti{OwnTracks-compatible format for Reitti} traccar{Traccar, OsmAnd protocol} other{Your own field names}}'**
  String shareTemplateHelp(String template);

  /// No description provided for @shareUrl.
  ///
  /// In en, this message translates to:
  /// **'Address (URL)'**
  String get shareUrl;

  /// No description provided for @shareUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter an address starting with http:// or https://.'**
  String get shareUrlInvalid;

  /// No description provided for @shareUrlWeb.
  ///
  /// In en, this message translates to:
  /// **'In the browser the server must allow CORS.'**
  String get shareUrlWeb;

  /// No description provided for @shareMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get shareMethod;

  /// No description provided for @shareAuth.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get shareAuth;

  /// No description provided for @shareAuthNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get shareAuthNone;

  /// No description provided for @shareUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get shareUsername;

  /// No description provided for @sharePassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get sharePassword;

  /// No description provided for @shareToken.
  ///
  /// In en, this message translates to:
  /// **'Token'**
  String get shareToken;

  /// No description provided for @shareFieldNames.
  ///
  /// In en, this message translates to:
  /// **'Field names'**
  String get shareFieldNames;

  /// No description provided for @shareFieldNamesHelp.
  ///
  /// In en, this message translates to:
  /// **'One per line as field=name, e.g. lat=latitude. Fields: lat, lon, acc, alt, vel, tst, bear.'**
  String get shareFieldNamesHelp;

  /// No description provided for @shareExtraFields.
  ///
  /// In en, this message translates to:
  /// **'Fixed fields'**
  String get shareExtraFields;

  /// No description provided for @shareExtraFieldsHelp.
  ///
  /// In en, this message translates to:
  /// **'One per line as name=value; sent with every point.'**
  String get shareExtraFieldsHelp;

  /// No description provided for @shareInterval.
  ///
  /// In en, this message translates to:
  /// **'Every … seconds'**
  String get shareInterval;

  /// No description provided for @shareMinDistance.
  ///
  /// In en, this message translates to:
  /// **'Or after … metres'**
  String get shareMinDistance;

  /// No description provided for @shareTest.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get shareTest;

  /// No description provided for @shareTestSucceeded.
  ///
  /// In en, this message translates to:
  /// **'The server received the point.'**
  String get shareTestSucceeded;

  /// No description provided for @shareTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String shareTestFailed(String error);

  /// No description provided for @shareStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get shareStatus;

  /// No description provided for @shareLastSent.
  ///
  /// In en, this message translates to:
  /// **'Last sent at {time}'**
  String shareLastSent(String time);

  /// No description provided for @shareNothingYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing sent yet'**
  String get shareNothingYet;

  /// No description provided for @shareQueued.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Queue empty} =1{1 point queued} other{{count} points queued}}'**
  String shareQueued(int count);

  /// No description provided for @shareError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String shareError(String error);

  /// No description provided for @shareStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped until you change the settings.'**
  String get shareStopped;

  /// No description provided for @shareClearQueue.
  ///
  /// In en, this message translates to:
  /// **'Clear queue'**
  String get shareClearQueue;

  /// No description provided for @shareExample.
  ///
  /// In en, this message translates to:
  /// **'Example'**
  String get shareExample;

  /// No description provided for @navigationNotificationSharing.
  ///
  /// In en, this message translates to:
  /// **'HomeMaps follows your location for the route and shares it with your server.'**
  String get navigationNotificationSharing;

  /// No description provided for @aboutHomeMaps.
  ///
  /// In en, this message translates to:
  /// **'About HomeMaps'**
  String get aboutHomeMaps;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String version(String version);

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'Navigation on your own server: map, routes, search and traffic.'**
  String get aboutDescription;

  /// No description provided for @sources.
  ///
  /// In en, this message translates to:
  /// **'Data and software'**
  String get sources;

  /// No description provided for @sourceMapData.
  ///
  /// In en, this message translates to:
  /// **'Map data © OpenStreetMap contributors'**
  String get sourceMapData;

  /// No description provided for @sourceTiles.
  ///
  /// In en, this message translates to:
  /// **'Map tiles and style'**
  String get sourceTiles;

  /// No description provided for @sourceRouting.
  ///
  /// In en, this message translates to:
  /// **'Routing and navigation'**
  String get sourceRouting;

  /// No description provided for @sourceSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get sourceSearch;

  /// No description provided for @sourceTraffic.
  ///
  /// In en, this message translates to:
  /// **'Traffic, roadworks and lane signals'**
  String get sourceTraffic;

  /// No description provided for @sourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get sourceCode;

  /// No description provided for @licenses.
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get licenses;

  /// No description provided for @dawarich.
  ///
  /// In en, this message translates to:
  /// **'Dawarich'**
  String get dawarich;

  /// No description provided for @dawarichHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter the address of your own Dawarich. Then sign in, and you can share your location with your family, record your trips while navigating and see family members on the map.'**
  String get dawarichHelp;

  /// No description provided for @dawarichNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get dawarichNotSignedIn;

  /// No description provided for @dawarichServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get dawarichServer;

  /// No description provided for @dawarichWithKey.
  ///
  /// In en, this message translates to:
  /// **'With an API key'**
  String get dawarichWithKey;

  /// No description provided for @dawarichEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get dawarichEmail;

  /// No description provided for @dawarichPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get dawarichPassword;

  /// No description provided for @dawarichKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get dawarichKey;

  /// No description provided for @dawarichKeyHelp.
  ///
  /// In en, this message translates to:
  /// **'Found in Dawarich under Settings.'**
  String get dawarichKeyHelp;

  /// No description provided for @dawarichSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get dawarichSignIn;

  /// No description provided for @dawarichSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get dawarichSignOut;

  /// No description provided for @dawarichCode.
  ///
  /// In en, this message translates to:
  /// **'Two-factor code'**
  String get dawarichCode;

  /// No description provided for @dawarichCodeHelp.
  ///
  /// In en, this message translates to:
  /// **'The code from your authenticator app, or a backup code.'**
  String get dawarichCodeHelp;

  /// No description provided for @dawarichConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get dawarichConfirm;

  /// No description provided for @cancelLabel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelLabel;

  /// No description provided for @dawarichErrorCredentials.
  ///
  /// In en, this message translates to:
  /// **'Incorrect credentials.'**
  String get dawarichErrorCredentials;

  /// No description provided for @dawarichErrorPasswordDisabled.
  ///
  /// In en, this message translates to:
  /// **'This server does not allow signing in with a password. Use an API key.'**
  String get dawarichErrorPasswordDisabled;

  /// No description provided for @dawarichErrorBlocked.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong codes. Try again later.'**
  String get dawarichErrorBlocked;

  /// No description provided for @dawarichErrorConnection.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach Dawarich ({detail}).'**
  String dawarichErrorConnection(String detail);

  /// No description provided for @dawarichErrorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong ({detail}).'**
  String dawarichErrorUnknown(String detail);

  /// No description provided for @dawarichSignedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {email}'**
  String dawarichSignedInAs(String email);

  /// No description provided for @dawarichFamily.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get dawarichFamily;

  /// No description provided for @dawarichShareWithFamily.
  ///
  /// In en, this message translates to:
  /// **'Share location with family'**
  String get dawarichShareWithFamily;

  /// No description provided for @dawarichSharingUntil.
  ///
  /// In en, this message translates to:
  /// **'Until {time}'**
  String dawarichSharingUntil(String time);

  /// No description provided for @dawarichSharingAlways.
  ///
  /// In en, this message translates to:
  /// **'Until you turn it off'**
  String get dawarichSharingAlways;

  /// No description provided for @dawarichNotSharing.
  ///
  /// In en, this message translates to:
  /// **'Your family can\'t see your location'**
  String get dawarichNotSharing;

  /// No description provided for @dawarichNoFamily.
  ///
  /// In en, this message translates to:
  /// **'You\'re not in a family yet. Create or join one on the Dawarich website.'**
  String get dawarichNoFamily;

  /// No description provided for @dawarichOpenWebsite.
  ///
  /// In en, this message translates to:
  /// **'Open website'**
  String get dawarichOpenWebsite;

  /// No description provided for @dawarichNoSubscription.
  ///
  /// In en, this message translates to:
  /// **'Family is not included in your Dawarich plan.'**
  String get dawarichNoSubscription;

  /// No description provided for @dawarichHowLong.
  ///
  /// In en, this message translates to:
  /// **'Share for how long?'**
  String get dawarichHowLong;

  /// No description provided for @dawarichDuration.
  ///
  /// In en, this message translates to:
  /// **'{duration, select, hour1{1 hour} hour6{6 hours} hour12{12 hours} hour24{24 hours} other{Until I turn it off}}'**
  String dawarichDuration(String duration);

  /// No description provided for @dawarichShareEnRoute.
  ///
  /// In en, this message translates to:
  /// **'Share location while navigating'**
  String get dawarichShareEnRoute;

  /// No description provided for @dawarichShareEnRouteHelp.
  ///
  /// In en, this message translates to:
  /// **'Sends your trip to Dawarich. Set interval and distance under Location sharing.'**
  String get dawarichShareEnRouteHelp;

  /// No description provided for @dawarichShowFamily.
  ///
  /// In en, this message translates to:
  /// **'Family members on the map'**
  String get dawarichShowFamily;

  /// No description provided for @dawarichShowFamilyHelp.
  ///
  /// In en, this message translates to:
  /// **'Updated every 30 seconds while the app is open.'**
  String get dawarichShowFamilyHelp;

  /// No description provided for @dawarichFamilySharing.
  ///
  /// In en, this message translates to:
  /// **'family sharing'**
  String get dawarichFamilySharing;

  /// No description provided for @shareViaDawarich.
  ///
  /// In en, this message translates to:
  /// **'Set up through your Dawarich account.'**
  String get shareViaDawarich;

  /// No description provided for @familyMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =0{just now} =1{1 minute ago} other{{minutes} minutes ago}}'**
  String familyMinutesAgo(int minutes);

  /// No description provided for @familyBattery.
  ///
  /// In en, this message translates to:
  /// **'battery {percent}%'**
  String familyBattery(int percent);

  /// No description provided for @familyHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{1 hour ago} other{{hours} hours ago}}'**
  String familyHoursAgo(int hours);

  /// No description provided for @familyDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day ago} other{{days} days ago}}'**
  String familyDaysAgo(int days);

  /// No description provided for @familyFollow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get familyFollow;

  /// No description provided for @familyFollowing.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get familyFollowing;

  /// No description provided for @settingsGroupMap.
  ///
  /// In en, this message translates to:
  /// **'Map and route'**
  String get settingsGroupMap;

  /// No description provided for @settingsGroupSharing.
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get settingsGroupSharing;

  /// No description provided for @settingsGroupApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsGroupApp;

  /// No description provided for @settingsMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get settingsMap;

  /// No description provided for @dayAndNight.
  ///
  /// In en, this message translates to:
  /// **'Day and night'**
  String get dayAndNight;

  /// No description provided for @themeOnlyMap.
  ///
  /// In en, this message translates to:
  /// **'Only for the Map style; Light and Dark are already a choice.'**
  String get themeOnlyMap;

  /// No description provided for @layers.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get layers;

  /// No description provided for @trafficOnMapHelp.
  ///
  /// In en, this message translates to:
  /// **'Closures, road works and traffic jams on the map'**
  String get trafficOnMapHelp;

  /// No description provided for @transport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get transport;

  /// No description provided for @transportHelp.
  ///
  /// In en, this message translates to:
  /// **'Used to calculate a new route.'**
  String get transportHelp;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @aboutSummary.
  ///
  /// In en, this message translates to:
  /// **'Version, sources and licenses'**
  String get aboutSummary;

  /// No description provided for @dawarichAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get dawarichAccount;

  /// No description provided for @dawarichNavigation.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get dawarichNavigation;

  /// No description provided for @shareConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get shareConnection;

  /// No description provided for @sharePoints.
  ///
  /// In en, this message translates to:
  /// **'Points'**
  String get sharePoints;

  /// No description provided for @dawarichWebsiteHelp.
  ///
  /// In en, this message translates to:
  /// **'Also for OIDC, such as Keycloak or Authentik. Not with Google.'**
  String get dawarichWebsiteHelp;

  /// No description provided for @dawarichWebsiteSignIn.
  ///
  /// In en, this message translates to:
  /// **'Via the Dawarich website'**
  String get dawarichWebsiteSignIn;

  /// No description provided for @dawarichWebsiteTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to Dawarich'**
  String get dawarichWebsiteTitle;

  /// No description provided for @dawarichWebsiteError.
  ///
  /// In en, this message translates to:
  /// **'The page does not load: {error}'**
  String dawarichWebsiteError(String error);

  /// No description provided for @dawarichErrorCors.
  ///
  /// In en, this message translates to:
  /// **'Dawarich cannot be reached from the browser. Dawarich does not allow this itself (CORS); add CORS headers for /api/v1 in your reverse proxy, or use the Android app.'**
  String get dawarichErrorCors;

  /// No description provided for @dawarichErrorNotDawarich.
  ///
  /// In en, this message translates to:
  /// **'No Dawarich answers at this address. If a login proxy (such as Authelia) is in front of it, let /api/v1 through.'**
  String get dawarichErrorNotDawarich;

  /// No description provided for @dawarichStepServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get dawarichStepServer;

  /// No description provided for @dawarichConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get dawarichConnect;

  /// No description provided for @dawarichConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get dawarichConnected;

  /// No description provided for @dawarichConnectedVersion.
  ///
  /// In en, this message translates to:
  /// **'Connected · Dawarich {version}'**
  String dawarichConnectedVersion(String version);

  /// No description provided for @dawarichChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get dawarichChange;

  /// No description provided for @dawarichStepSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get dawarichStepSignIn;

  /// No description provided for @dawarichOtherWays.
  ///
  /// In en, this message translates to:
  /// **'Other ways'**
  String get dawarichOtherWays;

  /// No description provided for @dawarichSignOutQuestion.
  ///
  /// In en, this message translates to:
  /// **'Sign out of Dawarich?'**
  String get dawarichSignOutQuestion;

  /// No description provided for @dawarichSignOutHelp.
  ///
  /// In en, this message translates to:
  /// **'Sharing while navigating stops, and your family disappears from the map.'**
  String get dawarichSignOutHelp;

  /// No description provided for @dawarichChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking connection…'**
  String get dawarichChecking;

  /// No description provided for @dawarichSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Session expired'**
  String get dawarichSessionExpired;

  /// No description provided for @dawarichSessionExpiredHelp.
  ///
  /// In en, this message translates to:
  /// **'Your API key no longer works. Sign in again.'**
  String get dawarichSessionExpiredHelp;

  /// No description provided for @dawarichUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Not reachable'**
  String get dawarichUnreachable;

  /// No description provided for @dawarichSignInAgain.
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get dawarichSignInAgain;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'nl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'nl':
      return AppLocalizationsNl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
