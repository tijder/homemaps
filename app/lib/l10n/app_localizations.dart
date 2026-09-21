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

  /// No description provided for @appTitel.
  ///
  /// In nl, this message translates to:
  /// **'HomeMaps'**
  String get appTitel;

  /// No description provided for @van.
  ///
  /// In nl, this message translates to:
  /// **'Van'**
  String get van;

  /// No description provided for @naar.
  ///
  /// In nl, this message translates to:
  /// **'Naar'**
  String get naar;

  /// No description provided for @via.
  ///
  /// In nl, this message translates to:
  /// **'Via'**
  String get via;

  /// No description provided for @zoekPlaats.
  ///
  /// In nl, this message translates to:
  /// **'Zoek een plaats of adres'**
  String get zoekPlaats;

  /// No description provided for @viaToevoegen.
  ///
  /// In nl, this message translates to:
  /// **'Tussenpunt toevoegen'**
  String get viaToevoegen;

  /// No description provided for @omdraaien.
  ///
  /// In nl, this message translates to:
  /// **'Heen en terug omdraaien'**
  String get omdraaien;

  /// No description provided for @verwijderen.
  ///
  /// In nl, this message translates to:
  /// **'Verwijderen'**
  String get verwijderen;

  /// No description provided for @wissen.
  ///
  /// In nl, this message translates to:
  /// **'Route wissen'**
  String get wissen;

  /// No description provided for @profielAuto.
  ///
  /// In nl, this message translates to:
  /// **'Auto'**
  String get profielAuto;

  /// No description provided for @profielFiets.
  ///
  /// In nl, this message translates to:
  /// **'Fiets'**
  String get profielFiets;

  /// No description provided for @profielLopen.
  ///
  /// In nl, this message translates to:
  /// **'Lopen'**
  String get profielLopen;

  /// No description provided for @opties.
  ///
  /// In nl, this message translates to:
  /// **'Opties'**
  String get opties;

  /// No description provided for @liveVerkeer.
  ///
  /// In nl, this message translates to:
  /// **'Actueel verkeer meenemen'**
  String get liveVerkeer;

  /// No description provided for @liveVerkeerUitleg.
  ///
  /// In nl, this message translates to:
  /// **'Files en afsluitingen van nu; alleen voor de auto'**
  String get liveVerkeerUitleg;

  /// No description provided for @vermijdSnelwegen.
  ///
  /// In nl, this message translates to:
  /// **'Snelwegen vermijden'**
  String get vermijdSnelwegen;

  /// No description provided for @vermijdTol.
  ///
  /// In nl, this message translates to:
  /// **'Tolwegen vermijden'**
  String get vermijdTol;

  /// No description provided for @vermijdVeren.
  ///
  /// In nl, this message translates to:
  /// **'Veerponten vermijden'**
  String get vermijdVeren;

  /// No description provided for @routeBezig.
  ///
  /// In nl, this message translates to:
  /// **'Route berekenen…'**
  String get routeBezig;

  /// No description provided for @geenRoute.
  ///
  /// In nl, this message translates to:
  /// **'Geen route gevonden tussen deze punten.'**
  String get geenRoute;

  /// No description provided for @geenWegInDeBuurt.
  ///
  /// In nl, this message translates to:
  /// **'Bij een van de punten ligt geen weg die je met dit vervoermiddel kunt gebruiken.'**
  String get geenWegInDeBuurt;

  /// No description provided for @serverOnbereikbaar.
  ///
  /// In nl, this message translates to:
  /// **'De server is niet bereikbaar.'**
  String get serverOnbereikbaar;

  /// No description provided for @snelste.
  ///
  /// In nl, this message translates to:
  /// **'Snelste'**
  String get snelste;

  /// No description provided for @alternatief.
  ///
  /// In nl, this message translates to:
  /// **'Alternatief {nummer}'**
  String alternatief(int nummer);

  /// No description provided for @stijgingDaling.
  ///
  /// In nl, this message translates to:
  /// **'+{stijging} m / -{daling} m'**
  String stijgingDaling(int stijging, int daling);

  /// No description provided for @metTol.
  ///
  /// In nl, this message translates to:
  /// **'tol'**
  String get metTol;

  /// No description provided for @metVeer.
  ///
  /// In nl, this message translates to:
  /// **'veerpont'**
  String get metVeer;

  /// No description provided for @instructies.
  ///
  /// In nl, this message translates to:
  /// **'Routebeschrijving'**
  String get instructies;

  /// No description provided for @hoogteprofiel.
  ///
  /// In nl, this message translates to:
  /// **'Hoogteprofiel'**
  String get hoogteprofiel;

  /// No description provided for @hierVandaan.
  ///
  /// In nl, this message translates to:
  /// **'Route vanaf hier'**
  String get hierVandaan;

  /// No description provided for @hierNaartoe.
  ///
  /// In nl, this message translates to:
  /// **'Route hierheen'**
  String get hierNaartoe;

  /// No description provided for @alsTussenpunt.
  ///
  /// In nl, this message translates to:
  /// **'Als tussenpunt'**
  String get alsTussenpunt;

  /// No description provided for @kaartstijl.
  ///
  /// In nl, this message translates to:
  /// **'Kaartstijl'**
  String get kaartstijl;

  /// No description provided for @stijlKaart.
  ///
  /// In nl, this message translates to:
  /// **'Kaart'**
  String get stijlKaart;

  /// No description provided for @stijlLicht.
  ///
  /// In nl, this message translates to:
  /// **'Licht'**
  String get stijlLicht;

  /// No description provided for @stijlDonker.
  ///
  /// In nl, this message translates to:
  /// **'Donker'**
  String get stijlDonker;

  /// No description provided for @instellingen.
  ///
  /// In nl, this message translates to:
  /// **'Instellingen'**
  String get instellingen;

  /// No description provided for @server.
  ///
  /// In nl, this message translates to:
  /// **'Server'**
  String get server;

  /// No description provided for @serverUitleg.
  ///
  /// In nl, this message translates to:
  /// **'Het adres van je HomeMaps-installatie, bijvoorbeeld https://maps.example.org'**
  String get serverUitleg;

  /// No description provided for @serverOngeldig.
  ///
  /// In nl, this message translates to:
  /// **'Vul een adres in dat met http:// of https:// begint.'**
  String get serverOngeldig;

  /// No description provided for @opslaan.
  ///
  /// In nl, this message translates to:
  /// **'Opslaan'**
  String get opslaan;

  /// No description provided for @serverNodig.
  ///
  /// In nl, this message translates to:
  /// **'Stel eerst het adres van je server in.'**
  String get serverNodig;

  /// No description provided for @over.
  ///
  /// In nl, this message translates to:
  /// **'Over'**
  String get over;

  /// No description provided for @overTekst.
  ///
  /// In nl, this message translates to:
  /// **'Kaart © OpenMapTiles © OpenStreetMap-bijdragers. Routes: Valhalla. Zoeken: Photon. Verkeer: NDW open data.'**
  String get overTekst;

  /// No description provided for @noordBoven.
  ///
  /// In nl, this message translates to:
  /// **'Noorden boven'**
  String get noordBoven;
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
