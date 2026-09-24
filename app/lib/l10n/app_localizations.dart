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

  /// No description provided for @themaAutomatisch.
  ///
  /// In nl, this message translates to:
  /// **'Automatisch'**
  String get themaAutomatisch;

  /// No description provided for @themaDag.
  ///
  /// In nl, this message translates to:
  /// **'Altijd dag'**
  String get themaDag;

  /// No description provided for @themaNacht.
  ///
  /// In nl, this message translates to:
  /// **'Altijd nacht'**
  String get themaNacht;

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

  /// No description provided for @noordBoven.
  ///
  /// In nl, this message translates to:
  /// **'Noorden boven'**
  String get noordBoven;

  /// No description provided for @zoekHier.
  ///
  /// In nl, this message translates to:
  /// **'Zoek op de kaart'**
  String get zoekHier;

  /// No description provided for @route.
  ///
  /// In nl, this message translates to:
  /// **'Route'**
  String get route;

  /// No description provided for @terugNaarZoeken.
  ///
  /// In nl, this message translates to:
  /// **'Terug naar zoeken'**
  String get terugNaarZoeken;

  /// No description provided for @sleepOmTeVerplaatsen.
  ///
  /// In nl, this message translates to:
  /// **'Sleep om de volgorde te wijzigen'**
  String get sleepOmTeVerplaatsen;

  /// No description provided for @verkeerOpKaart.
  ///
  /// In nl, this message translates to:
  /// **'Verkeer'**
  String get verkeerOpKaart;

  /// No description provided for @verkeerWegDicht.
  ///
  /// In nl, this message translates to:
  /// **'Weg afgesloten'**
  String get verkeerWegDicht;

  /// No description provided for @verkeerAfritDicht.
  ///
  /// In nl, this message translates to:
  /// **'Afrit afgesloten'**
  String get verkeerAfritDicht;

  /// No description provided for @verkeerOpritDicht.
  ///
  /// In nl, this message translates to:
  /// **'Oprit afgesloten'**
  String get verkeerOpritDicht;

  /// No description provided for @verkeerVerbindingswegDicht.
  ///
  /// In nl, this message translates to:
  /// **'Verbindingsweg afgesloten'**
  String get verkeerVerbindingswegDicht;

  /// No description provided for @verkeerParallelbaanDicht.
  ///
  /// In nl, this message translates to:
  /// **'Parallelbaan afgesloten'**
  String get verkeerParallelbaanDicht;

  /// No description provided for @verkeerRijbaanDicht.
  ///
  /// In nl, this message translates to:
  /// **'Rijbaan afgesloten'**
  String get verkeerRijbaanDicht;

  /// No description provided for @verkeerRijstrookDicht.
  ///
  /// In nl, this message translates to:
  /// **'Rijstrook afgesloten'**
  String get verkeerRijstrookDicht;

  /// No description provided for @verkeerStrokenOpen.
  ///
  /// In nl, this message translates to:
  /// **'{aantal, plural, =1{1 rijstrook open} other{{aantal} rijstroken open}}'**
  String verkeerStrokenOpen(int aantal);

  /// No description provided for @verkeerFile.
  ///
  /// In nl, this message translates to:
  /// **'File'**
  String get verkeerFile;

  /// No description provided for @verkeerTraag.
  ///
  /// In nl, this message translates to:
  /// **'Langzaam verkeer'**
  String get verkeerTraag;

  /// No description provided for @verkeerVertraging.
  ///
  /// In nl, this message translates to:
  /// **'+{duur} vertraging · {kmu} km/u'**
  String verkeerVertraging(String duur, int kmu);

  /// No description provided for @verkeerTot.
  ///
  /// In nl, this message translates to:
  /// **'Tot {moment}'**
  String verkeerTot(String moment);

  /// No description provided for @oorzaakWerk.
  ///
  /// In nl, this message translates to:
  /// **'Werkzaamheden'**
  String get oorzaakWerk;

  /// No description provided for @oorzaakOngeval.
  ///
  /// In nl, this message translates to:
  /// **'Ongeval'**
  String get oorzaakOngeval;

  /// No description provided for @oorzaakEvenement.
  ///
  /// In nl, this message translates to:
  /// **'Evenement'**
  String get oorzaakEvenement;

  /// No description provided for @mijnLocatie.
  ///
  /// In nl, this message translates to:
  /// **'Mijn locatie'**
  String get mijnLocatie;

  /// No description provided for @locatieGeweigerd.
  ///
  /// In nl, this message translates to:
  /// **'Zonder toestemming kan de app je locatie niet tonen.'**
  String get locatieGeweigerd;

  /// No description provided for @locatieNooit.
  ///
  /// In nl, this message translates to:
  /// **'Locatie is voor HomeMaps geweigerd. Zet het aan in de instellingen van je telefoon.'**
  String get locatieNooit;

  /// No description provided for @locatieNooitWeb.
  ///
  /// In nl, this message translates to:
  /// **'Locatie is voor deze site geblokkeerd. Sta het toe via het slotje naast het adres.'**
  String get locatieNooitWeb;

  /// No description provided for @locatieDienstUit.
  ///
  /// In nl, this message translates to:
  /// **'Locatie staat uit op je apparaat.'**
  String get locatieDienstUit;

  /// No description provided for @locatieNietGevonden.
  ///
  /// In nl, this message translates to:
  /// **'Je apparaat kan je locatie niet bepalen; het blijft zoeken. Op een computer lukt dat vaak niet, op een telefoon wel.'**
  String get locatieNietGevonden;

  /// No description provided for @startNavigatie.
  ///
  /// In nl, this message translates to:
  /// **'Start'**
  String get startNavigatie;

  /// No description provided for @navigatieMeldingTitel.
  ///
  /// In nl, this message translates to:
  /// **'Navigatie naar {bestemming}'**
  String navigatieMeldingTitel(String bestemming);

  /// No description provided for @navigatieMeldingTekst.
  ///
  /// In nl, this message translates to:
  /// **'HomeMaps volgt je locatie voor de route.'**
  String get navigatieMeldingTekst;

  /// No description provided for @herberekenen.
  ///
  /// In nl, this message translates to:
  /// **'Route wordt herberekend.'**
  String get herberekenen;

  /// No description provided for @herberekenenBezig.
  ///
  /// In nl, this message translates to:
  /// **'Route herberekenen…'**
  String get herberekenenBezig;

  /// No description provided for @snellereRoute.
  ///
  /// In nl, this message translates to:
  /// **'{minuten, plural, =1{Er is een snellere route, 1 minuut sneller. Kies op het scherm of je hem neemt.} other{Er is een snellere route, {minuten} minuten sneller. Kies op het scherm of je hem neemt.}}'**
  String snellereRoute(int minuten);

  /// No description provided for @overAfstand.
  ///
  /// In nl, this message translates to:
  /// **'Over {afstand} {zin}'**
  String overAfstand(String afstand, String zin);

  /// No description provided for @gesprokenMeter.
  ///
  /// In nl, this message translates to:
  /// **'{meter} meter'**
  String gesprokenMeter(int meter);

  /// No description provided for @gesprokenKilometer.
  ///
  /// In nl, this message translates to:
  /// **'{km} kilometer'**
  String gesprokenKilometer(String km);

  /// No description provided for @aangekomen.
  ///
  /// In nl, this message translates to:
  /// **'Je bent er'**
  String get aangekomen;

  /// No description provided for @klaar.
  ///
  /// In nl, this message translates to:
  /// **'Klaar'**
  String get klaar;

  /// Wat je doet bij een op- of afrit, splitsing of invoegstrook, kort, in de navigatiekop.
  ///
  /// In nl, this message translates to:
  /// **'{soort, select, oprit{Oprit nemen} afrit{Afrit nemen} rechtdoor{Rechtdoor aanhouden} rechts{Rechts aanhouden} links{Links aanhouden} invoegen{Invoegen} other{}}'**
  String korteActie(String soort);

  /// No description provided for @afrit.
  ///
  /// In nl, this message translates to:
  /// **'Afrit {nummer}'**
  String afrit(String nummer);

  /// No description provided for @rijstrokenOver.
  ///
  /// In nl, this message translates to:
  /// **'Over {afstand}: {stroken}'**
  String rijstrokenOver(String afstand, String stroken);

  /// No description provided for @rijstrokenGoed.
  ///
  /// In nl, this message translates to:
  /// **'{goed, plural, =1{1 goede rijstrook} other{{goed} goede rijstroken}} van {totaal}'**
  String rijstrokenGoed(int goed, int totaal);

  /// No description provided for @hervatten.
  ///
  /// In nl, this message translates to:
  /// **'Hervatten'**
  String get hervatten;

  /// No description provided for @stopNavigatie.
  ///
  /// In nl, this message translates to:
  /// **'Stop'**
  String get stopNavigatie;

  /// No description provided for @stemUit.
  ///
  /// In nl, this message translates to:
  /// **'Stem uit'**
  String get stemUit;

  /// No description provided for @stemAan.
  ///
  /// In nl, this message translates to:
  /// **'Stem aan'**
  String get stemAan;

  /// No description provided for @aankomst.
  ///
  /// In nl, this message translates to:
  /// **'Aankomst {tijd}'**
  String aankomst(String tijd);

  /// No description provided for @daarna.
  ///
  /// In nl, this message translates to:
  /// **'Daarna'**
  String get daarna;

  /// No description provided for @locatieZoeken.
  ///
  /// In nl, this message translates to:
  /// **'Locatie zoeken…'**
  String get locatieZoeken;

  /// No description provided for @locatieAanOmTeNavigeren.
  ///
  /// In nl, this message translates to:
  /// **'Locatie aanzetten om te navigeren'**
  String get locatieAanOmTeNavigeren;

  /// No description provided for @navigerenZonderLocatie.
  ///
  /// In nl, this message translates to:
  /// **'Navigeren kan pas als je locatie bekend is.'**
  String get navigerenZonderLocatie;

  /// No description provided for @opnieuwProberen.
  ///
  /// In nl, this message translates to:
  /// **'Opnieuw proberen'**
  String get opnieuwProberen;

  /// No description provided for @aantalTussenpunten.
  ///
  /// In nl, this message translates to:
  /// **'{aantal, plural, =1{via 1 tussenpunt} other{via {aantal} tussenpunten}}'**
  String aantalTussenpunten(int aantal);

  /// No description provided for @routeWijzigen.
  ///
  /// In nl, this message translates to:
  /// **'Route wijzigen'**
  String get routeWijzigen;

  /// No description provided for @eerstStoppen.
  ///
  /// In nl, this message translates to:
  /// **'Stop eerst de navigatie.'**
  String get eerstStoppen;

  /// No description provided for @vertraging.
  ///
  /// In nl, this message translates to:
  /// **'vertraging'**
  String get vertraging;

  /// No description provided for @voorstelSneller.
  ///
  /// In nl, this message translates to:
  /// **'Snellere route: {minuten} min sneller'**
  String voorstelSneller(int minuten);

  /// No description provided for @voorstelVia.
  ///
  /// In nl, this message translates to:
  /// **'via {weg}'**
  String voorstelVia(String weg);

  /// No description provided for @nemen.
  ///
  /// In nl, this message translates to:
  /// **'Nemen'**
  String get nemen;

  /// No description provided for @negeren.
  ///
  /// In nl, this message translates to:
  /// **'Negeren'**
  String get negeren;

  /// No description provided for @aankomstOm.
  ///
  /// In nl, this message translates to:
  /// **'aankomst {tijd}'**
  String aankomstOm(String tijd);

  /// No description provided for @thuis.
  ///
  /// In nl, this message translates to:
  /// **'Thuis'**
  String get thuis;

  /// No description provided for @werk.
  ///
  /// In nl, this message translates to:
  /// **'Werk'**
  String get werk;

  /// No description provided for @alsThuis.
  ///
  /// In nl, this message translates to:
  /// **'Als thuis'**
  String get alsThuis;

  /// No description provided for @alsWerk.
  ///
  /// In nl, this message translates to:
  /// **'Als werk'**
  String get alsWerk;

  /// No description provided for @plekken.
  ///
  /// In nl, this message translates to:
  /// **'Plekken'**
  String get plekken;

  /// No description provided for @plekkenUitleg.
  ///
  /// In nl, this message translates to:
  /// **'Thuis en werk stel je in op het kaartje van een gevonden plek.'**
  String get plekkenUitleg;

  /// No description provided for @nietIngesteld.
  ///
  /// In nl, this message translates to:
  /// **'Niet ingesteld'**
  String get nietIngesteld;

  /// No description provided for @recentePlekken.
  ///
  /// In nl, this message translates to:
  /// **'Recente plekken'**
  String get recentePlekken;

  /// No description provided for @aantalPlekken.
  ///
  /// In nl, this message translates to:
  /// **'{aantal, plural, =0{Geen} =1{1 plek} other{{aantal} plekken}}'**
  String aantalPlekken(int aantal);

  /// No description provided for @wissenKort.
  ///
  /// In nl, this message translates to:
  /// **'Wissen'**
  String get wissenKort;

  /// No description provided for @nietGevonden.
  ///
  /// In nl, this message translates to:
  /// **'Niet gevonden: {zoek}'**
  String nietGevonden(String zoek);

  /// No description provided for @kmu.
  ///
  /// In nl, this message translates to:
  /// **'km/u'**
  String get kmu;

  /// No description provided for @maximumsnelheid.
  ///
  /// In nl, this message translates to:
  /// **'Maximumsnelheid {kmu} km/u'**
  String maximumsnelheid(int kmu);

  /// No description provided for @maximumsnelheidTijdelijk.
  ///
  /// In nl, this message translates to:
  /// **'Tijdelijke maximumsnelheid {kmu} km/u'**
  String maximumsnelheidTijdelijk(int kmu);

  /// No description provided for @maximumsnelheidMatrix.
  ///
  /// In nl, this message translates to:
  /// **'Maximumsnelheid {kmu} km/u op de matrixborden'**
  String maximumsnelheidMatrix(int kmu);

  /// No description provided for @meldingOngeval.
  ///
  /// In nl, this message translates to:
  /// **'Ongeval'**
  String get meldingOngeval;

  /// No description provided for @meldingPech.
  ///
  /// In nl, this message translates to:
  /// **'Pechgeval'**
  String get meldingPech;

  /// No description provided for @meldingObstakel.
  ///
  /// In nl, this message translates to:
  /// **'Voorwerp op de weg'**
  String get meldingObstakel;

  /// No description provided for @meldingBrug.
  ///
  /// In nl, this message translates to:
  /// **'Open brug'**
  String get meldingBrug;

  /// No description provided for @matrixborden.
  ///
  /// In nl, this message translates to:
  /// **'Matrixborden'**
  String get matrixborden;

  /// No description provided for @meldingSinds.
  ///
  /// In nl, this message translates to:
  /// **'Sinds {tijd}'**
  String meldingSinds(String tijd);

  /// No description provided for @waarschuwingOpRoute.
  ///
  /// In nl, this message translates to:
  /// **'Let op: {melding} over {afstand}.'**
  String waarschuwingOpRoute(String melding, String afstand);

  /// No description provided for @vertrek.
  ///
  /// In nl, this message translates to:
  /// **'Vertrek'**
  String get vertrek;

  /// No description provided for @vertrekNu.
  ///
  /// In nl, this message translates to:
  /// **'Nu'**
  String get vertrekNu;

  /// No description provided for @vertrekLater.
  ///
  /// In nl, this message translates to:
  /// **'Later…'**
  String get vertrekLater;

  /// No description provided for @afsluitingOpRoute.
  ///
  /// In nl, this message translates to:
  /// **'{aantal, plural, =1{Geplande afsluiting op deze route: {venster}} other{{aantal} geplande afsluitingen op deze route, de eerste: {venster}}}'**
  String afsluitingOpRoute(String venster, int aantal);

  /// No description provided for @langsDeRoute.
  ///
  /// In nl, this message translates to:
  /// **'Langs de route'**
  String get langsDeRoute;

  /// No description provided for @langsTanken.
  ///
  /// In nl, this message translates to:
  /// **'Tanken'**
  String get langsTanken;

  /// No description provided for @langsLaden.
  ///
  /// In nl, this message translates to:
  /// **'Laden'**
  String get langsLaden;

  /// No description provided for @langsSupermarkt.
  ///
  /// In nl, this message translates to:
  /// **'Supermarkt'**
  String get langsSupermarkt;

  /// No description provided for @langsEten.
  ///
  /// In nl, this message translates to:
  /// **'Eten'**
  String get langsEten;

  /// No description provided for @langsNiets.
  ///
  /// In nl, this message translates to:
  /// **'Niets gevonden binnen een kilometer van de route.'**
  String get langsNiets;

  /// No description provided for @langsAfstand.
  ///
  /// In nl, this message translates to:
  /// **'{afstand} van de route'**
  String langsAfstand(String afstand);

  /// No description provided for @tussenstopToegevoegd.
  ///
  /// In nl, this message translates to:
  /// **'Tussenstop: {naam}'**
  String tussenstopToegevoegd(String naam);

  /// No description provided for @locatieDelen.
  ///
  /// In nl, this message translates to:
  /// **'Locatie delen'**
  String get locatieDelen;

  /// No description provided for @locatieDelenUitleg.
  ///
  /// In nl, this message translates to:
  /// **'Stuur je positie naar je eigen server, zoals Colota dat doet. Alleen tijdens het navigeren.'**
  String get locatieDelenUitleg;

  /// No description provided for @locatieDelenAan.
  ///
  /// In nl, this message translates to:
  /// **'Delen tijdens navigeren'**
  String get locatieDelenAan;

  /// No description provided for @deelUit.
  ///
  /// In nl, this message translates to:
  /// **'Uit'**
  String get deelUit;

  /// No description provided for @deelServer.
  ///
  /// In nl, this message translates to:
  /// **'Server'**
  String get deelServer;

  /// No description provided for @deelAangepast.
  ///
  /// In nl, this message translates to:
  /// **'Eigen server'**
  String get deelAangepast;

  /// No description provided for @deelSjabloonUitleg.
  ///
  /// In nl, this message translates to:
  /// **'{sjabloon, select, dawarich{Dawarich-API: punten in batches, met richting, batterij en vervoer} geopulse{Colota-formaat voor GeoPulse} overland{Overland: punten in batches (GeoJSON)} owntracks{Standaard OwnTracks over HTTP} phonetrack{Nextcloud PhoneTrack} reitti{OwnTracks-formaat voor Reitti} traccar{Traccar, OsmAnd-protocol} other{Je eigen veldnamen}}'**
  String deelSjabloonUitleg(String sjabloon);

  /// No description provided for @deelUrl.
  ///
  /// In nl, this message translates to:
  /// **'Adres (URL)'**
  String get deelUrl;

  /// No description provided for @deelUrlOngeldig.
  ///
  /// In nl, this message translates to:
  /// **'Vul een adres in dat met http:// of https:// begint.'**
  String get deelUrlOngeldig;

  /// No description provided for @deelUrlWeb.
  ///
  /// In nl, this message translates to:
  /// **'In de browser moet de server CORS toestaan.'**
  String get deelUrlWeb;

  /// No description provided for @deelMethode.
  ///
  /// In nl, this message translates to:
  /// **'Methode'**
  String get deelMethode;

  /// No description provided for @deelInlog.
  ///
  /// In nl, this message translates to:
  /// **'Inloggen'**
  String get deelInlog;

  /// No description provided for @deelInlogGeen.
  ///
  /// In nl, this message translates to:
  /// **'Geen'**
  String get deelInlogGeen;

  /// No description provided for @deelGebruiker.
  ///
  /// In nl, this message translates to:
  /// **'Gebruikersnaam'**
  String get deelGebruiker;

  /// No description provided for @deelWachtwoord.
  ///
  /// In nl, this message translates to:
  /// **'Wachtwoord'**
  String get deelWachtwoord;

  /// No description provided for @deelToken.
  ///
  /// In nl, this message translates to:
  /// **'Token'**
  String get deelToken;

  /// No description provided for @deelVeldnamen.
  ///
  /// In nl, this message translates to:
  /// **'Veldnamen'**
  String get deelVeldnamen;

  /// No description provided for @deelVeldnamenUitleg.
  ///
  /// In nl, this message translates to:
  /// **'Per regel veld=naam, bijvoorbeeld lat=latitude. Velden: lat, lon, acc, alt, vel, tst, bear.'**
  String get deelVeldnamenUitleg;

  /// No description provided for @deelExtraVelden.
  ///
  /// In nl, this message translates to:
  /// **'Vaste velden'**
  String get deelExtraVelden;

  /// No description provided for @deelExtraVeldenUitleg.
  ///
  /// In nl, this message translates to:
  /// **'Per regel naam=waarde; die gaan bij elk punt mee.'**
  String get deelExtraVeldenUitleg;

  /// No description provided for @deelInterval.
  ///
  /// In nl, this message translates to:
  /// **'Elke … seconden'**
  String get deelInterval;

  /// No description provided for @deelMinAfstand.
  ///
  /// In nl, this message translates to:
  /// **'Of na … meter'**
  String get deelMinAfstand;

  /// No description provided for @deelTesten.
  ///
  /// In nl, this message translates to:
  /// **'Verbinding testen'**
  String get deelTesten;

  /// No description provided for @deelTestGelukt.
  ///
  /// In nl, this message translates to:
  /// **'De server heeft het punt ontvangen.'**
  String get deelTestGelukt;

  /// No description provided for @deelTestMislukt.
  ///
  /// In nl, this message translates to:
  /// **'Niet gelukt: {fout}'**
  String deelTestMislukt(String fout);

  /// No description provided for @deelStatus.
  ///
  /// In nl, this message translates to:
  /// **'Status'**
  String get deelStatus;

  /// No description provided for @deelLaatst.
  ///
  /// In nl, this message translates to:
  /// **'Laatst verstuurd om {tijd}'**
  String deelLaatst(String tijd);

  /// No description provided for @deelNogNiets.
  ///
  /// In nl, this message translates to:
  /// **'Nog niets verstuurd'**
  String get deelNogNiets;

  /// No description provided for @deelInWachtrij.
  ///
  /// In nl, this message translates to:
  /// **'{aantal, plural, =0{Niets in de wachtrij} =1{1 punt in de wachtrij} other{{aantal} punten in de wachtrij}}'**
  String deelInWachtrij(int aantal);

  /// No description provided for @deelFout.
  ///
  /// In nl, this message translates to:
  /// **'Fout: {fout}'**
  String deelFout(String fout);

  /// No description provided for @deelGestopt.
  ///
  /// In nl, this message translates to:
  /// **'Gestopt tot je de instellingen wijzigt.'**
  String get deelGestopt;

  /// No description provided for @deelWisWachtrij.
  ///
  /// In nl, this message translates to:
  /// **'Wachtrij leegmaken'**
  String get deelWisWachtrij;

  /// No description provided for @deelVoorbeeld.
  ///
  /// In nl, this message translates to:
  /// **'Voorbeeld'**
  String get deelVoorbeeld;

  /// No description provided for @navigatieMeldingDelen.
  ///
  /// In nl, this message translates to:
  /// **'HomeMaps volgt je locatie voor de route en deelt hem met je server.'**
  String get navigatieMeldingDelen;

  /// No description provided for @overHomeMaps.
  ///
  /// In nl, this message translates to:
  /// **'Over HomeMaps'**
  String get overHomeMaps;

  /// No description provided for @versie.
  ///
  /// In nl, this message translates to:
  /// **'Versie {versie}'**
  String versie(String versie);

  /// No description provided for @overBeschrijving.
  ///
  /// In nl, this message translates to:
  /// **'Navigatie op je eigen server: kaart, routes, zoeken en verkeer.'**
  String get overBeschrijving;

  /// No description provided for @bronnen.
  ///
  /// In nl, this message translates to:
  /// **'Gegevens en software'**
  String get bronnen;

  /// No description provided for @bronKaartgegevens.
  ///
  /// In nl, this message translates to:
  /// **'Kaartgegevens © OpenStreetMap-bijdragers'**
  String get bronKaartgegevens;

  /// No description provided for @bronTegels.
  ///
  /// In nl, this message translates to:
  /// **'Kaarttegels en -stijl'**
  String get bronTegels;

  /// No description provided for @bronRoutes.
  ///
  /// In nl, this message translates to:
  /// **'Routes en navigatie'**
  String get bronRoutes;

  /// No description provided for @bronZoeken.
  ///
  /// In nl, this message translates to:
  /// **'Zoeken'**
  String get bronZoeken;

  /// No description provided for @bronVerkeer.
  ///
  /// In nl, this message translates to:
  /// **'Verkeer, werk en matrixborden'**
  String get bronVerkeer;

  /// No description provided for @broncode.
  ///
  /// In nl, this message translates to:
  /// **'Broncode'**
  String get broncode;

  /// No description provided for @licenties.
  ///
  /// In nl, this message translates to:
  /// **'Licenties'**
  String get licenties;

  /// No description provided for @dawarich.
  ///
  /// In nl, this message translates to:
  /// **'Dawarich'**
  String get dawarich;

  /// No description provided for @dawarichUitleg.
  ///
  /// In nl, this message translates to:
  /// **'Log in bij je eigen Dawarich-server om je locatie met je familie te delen, onderweg je rit bij te houden en familieleden op de kaart te zien.'**
  String get dawarichUitleg;

  /// No description provided for @dawarichNietIngelogd.
  ///
  /// In nl, this message translates to:
  /// **'Niet ingelogd'**
  String get dawarichNietIngelogd;

  /// No description provided for @dawarichServer.
  ///
  /// In nl, this message translates to:
  /// **'Server'**
  String get dawarichServer;

  /// No description provided for @dawarichMetWachtwoord.
  ///
  /// In nl, this message translates to:
  /// **'E-mail en wachtwoord'**
  String get dawarichMetWachtwoord;

  /// No description provided for @dawarichMetSleutel.
  ///
  /// In nl, this message translates to:
  /// **'API-sleutel'**
  String get dawarichMetSleutel;

  /// No description provided for @dawarichEmail.
  ///
  /// In nl, this message translates to:
  /// **'E-mail'**
  String get dawarichEmail;

  /// No description provided for @dawarichWachtwoord.
  ///
  /// In nl, this message translates to:
  /// **'Wachtwoord'**
  String get dawarichWachtwoord;

  /// No description provided for @dawarichSleutel.
  ///
  /// In nl, this message translates to:
  /// **'API-sleutel'**
  String get dawarichSleutel;

  /// No description provided for @dawarichSleutelUitleg.
  ///
  /// In nl, this message translates to:
  /// **'Te vinden in Dawarich onder Instellingen. Gebruik dit als je server alleen OIDC kent.'**
  String get dawarichSleutelUitleg;

  /// No description provided for @dawarichInloggen.
  ///
  /// In nl, this message translates to:
  /// **'Inloggen'**
  String get dawarichInloggen;

  /// No description provided for @dawarichUitloggen.
  ///
  /// In nl, this message translates to:
  /// **'Uitloggen'**
  String get dawarichUitloggen;

  /// No description provided for @dawarichCode.
  ///
  /// In nl, this message translates to:
  /// **'Code voor tweestapsverificatie'**
  String get dawarichCode;

  /// No description provided for @dawarichCodeUitleg.
  ///
  /// In nl, this message translates to:
  /// **'De code uit je authenticator-app, of een back-upcode.'**
  String get dawarichCodeUitleg;

  /// No description provided for @dawarichBevestig.
  ///
  /// In nl, this message translates to:
  /// **'Bevestigen'**
  String get dawarichBevestig;

  /// No description provided for @annuleren.
  ///
  /// In nl, this message translates to:
  /// **'Annuleren'**
  String get annuleren;

  /// No description provided for @dawarichWeb.
  ///
  /// In nl, this message translates to:
  /// **'In de browser moet Dawarich CORS toestaan voor dit adres.'**
  String get dawarichWeb;

  /// No description provided for @dawarichFoutInlog.
  ///
  /// In nl, this message translates to:
  /// **'Onjuiste gegevens.'**
  String get dawarichFoutInlog;

  /// No description provided for @dawarichFoutWachtwoordUit.
  ///
  /// In nl, this message translates to:
  /// **'Deze server staat inloggen met een wachtwoord niet toe. Gebruik een API-sleutel.'**
  String get dawarichFoutWachtwoordUit;

  /// No description provided for @dawarichFoutGeblokkeerd.
  ///
  /// In nl, this message translates to:
  /// **'Te vaak een verkeerde code. Probeer het later opnieuw.'**
  String get dawarichFoutGeblokkeerd;

  /// No description provided for @dawarichFoutVerbinding.
  ///
  /// In nl, this message translates to:
  /// **'Dawarich is niet te bereiken ({detail}).'**
  String dawarichFoutVerbinding(String detail);

  /// No description provided for @dawarichFoutOnbekend.
  ///
  /// In nl, this message translates to:
  /// **'Er ging iets mis ({detail}).'**
  String dawarichFoutOnbekend(String detail);

  /// No description provided for @dawarichIngelogdAls.
  ///
  /// In nl, this message translates to:
  /// **'Ingelogd als {email}'**
  String dawarichIngelogdAls(String email);

  /// No description provided for @dawarichFamilie.
  ///
  /// In nl, this message translates to:
  /// **'Familie'**
  String get dawarichFamilie;

  /// No description provided for @dawarichFamilieDelen.
  ///
  /// In nl, this message translates to:
  /// **'Locatie delen met familie'**
  String get dawarichFamilieDelen;

  /// No description provided for @dawarichDeeltTot.
  ///
  /// In nl, this message translates to:
  /// **'Tot {tijd}'**
  String dawarichDeeltTot(String tijd);

  /// No description provided for @dawarichDeeltAltijd.
  ///
  /// In nl, this message translates to:
  /// **'Tot je het uitzet'**
  String get dawarichDeeltAltijd;

  /// No description provided for @dawarichDeeltNiet.
  ///
  /// In nl, this message translates to:
  /// **'Je familie ziet je locatie niet'**
  String get dawarichDeeltNiet;

  /// No description provided for @dawarichGeenFamilie.
  ///
  /// In nl, this message translates to:
  /// **'Je zit nog niet in een familie. Maak er een of word lid op de Dawarich-website.'**
  String get dawarichGeenFamilie;

  /// No description provided for @dawarichNaarWebsite.
  ///
  /// In nl, this message translates to:
  /// **'Naar de website'**
  String get dawarichNaarWebsite;

  /// No description provided for @dawarichGeenAbonnement.
  ///
  /// In nl, this message translates to:
  /// **'Familie zit niet in je Dawarich-abonnement.'**
  String get dawarichGeenAbonnement;

  /// No description provided for @dawarichHoeLang.
  ///
  /// In nl, this message translates to:
  /// **'Hoe lang delen?'**
  String get dawarichHoeLang;

  /// No description provided for @dawarichDuur.
  ///
  /// In nl, this message translates to:
  /// **'{duur, select, uur1{1 uur} uur6{6 uur} uur12{12 uur} uur24{24 uur} other{Tot ik het uitzet}}'**
  String dawarichDuur(String duur);

  /// No description provided for @dawarichDelenOnderweg.
  ///
  /// In nl, this message translates to:
  /// **'Locatie delen tijdens navigeren'**
  String get dawarichDelenOnderweg;

  /// No description provided for @dawarichDelenOnderwegUitleg.
  ///
  /// In nl, this message translates to:
  /// **'Stuurt je rit naar Dawarich. Interval en afstand stel je in bij Locatie delen.'**
  String get dawarichDelenOnderwegUitleg;

  /// No description provided for @dawarichToonFamilie.
  ///
  /// In nl, this message translates to:
  /// **'Familieleden op de kaart'**
  String get dawarichToonFamilie;

  /// No description provided for @dawarichToonFamilieUitleg.
  ///
  /// In nl, this message translates to:
  /// **'Elke 30 seconden bijgewerkt, zolang de app open is.'**
  String get dawarichToonFamilieUitleg;

  /// No description provided for @dawarichFamilieDeelt.
  ///
  /// In nl, this message translates to:
  /// **'familie deelt'**
  String get dawarichFamilieDeelt;

  /// No description provided for @deelViaDawarich.
  ///
  /// In nl, this message translates to:
  /// **'Ingesteld via je Dawarich-account.'**
  String get deelViaDawarich;

  /// No description provided for @familieGeleden.
  ///
  /// In nl, this message translates to:
  /// **'{minuten, plural, =0{zojuist} =1{1 minuut geleden} other{{minuten} minuten geleden}}'**
  String familieGeleden(int minuten);

  /// No description provided for @familieBatterij.
  ///
  /// In nl, this message translates to:
  /// **'batterij {procent}%'**
  String familieBatterij(int procent);

  /// No description provided for @familieUrenGeleden.
  ///
  /// In nl, this message translates to:
  /// **'{uren, plural, =1{1 uur geleden} other{{uren} uur geleden}}'**
  String familieUrenGeleden(int uren);

  /// No description provided for @familieDagenGeleden.
  ///
  /// In nl, this message translates to:
  /// **'{dagen, plural, =1{1 dag geleden} other{{dagen} dagen geleden}}'**
  String familieDagenGeleden(int dagen);

  /// No description provided for @familieVolgen.
  ///
  /// In nl, this message translates to:
  /// **'Volgen'**
  String get familieVolgen;

  /// No description provided for @familieVolgt.
  ///
  /// In nl, this message translates to:
  /// **'Wordt gevolgd'**
  String get familieVolgt;

  /// No description provided for @instellingenGroepKaart.
  ///
  /// In nl, this message translates to:
  /// **'Kaart en route'**
  String get instellingenGroepKaart;

  /// No description provided for @instellingenGroepDelen.
  ///
  /// In nl, this message translates to:
  /// **'Delen'**
  String get instellingenGroepDelen;

  /// No description provided for @instellingenGroepApp.
  ///
  /// In nl, this message translates to:
  /// **'App'**
  String get instellingenGroepApp;

  /// No description provided for @instellingenKaart.
  ///
  /// In nl, this message translates to:
  /// **'Kaart'**
  String get instellingenKaart;

  /// No description provided for @dagEnNacht.
  ///
  /// In nl, this message translates to:
  /// **'Dag en nacht'**
  String get dagEnNacht;

  /// No description provided for @themaAlleenKaart.
  ///
  /// In nl, this message translates to:
  /// **'Alleen bij de stijl Kaart; Licht en Donker zijn al een keuze.'**
  String get themaAlleenKaart;

  /// No description provided for @lagen.
  ///
  /// In nl, this message translates to:
  /// **'Lagen'**
  String get lagen;

  /// No description provided for @verkeerOpKaartUitleg.
  ///
  /// In nl, this message translates to:
  /// **'Afsluitingen, werk op de weg en files op de kaart'**
  String get verkeerOpKaartUitleg;

  /// No description provided for @vervoer.
  ///
  /// In nl, this message translates to:
  /// **'Vervoer'**
  String get vervoer;

  /// No description provided for @vervoerUitleg.
  ///
  /// In nl, this message translates to:
  /// **'Waarmee een nieuwe route berekend wordt.'**
  String get vervoerUitleg;

  /// No description provided for @opgeslagen.
  ///
  /// In nl, this message translates to:
  /// **'Opgeslagen'**
  String get opgeslagen;

  /// No description provided for @overSamenvatting.
  ///
  /// In nl, this message translates to:
  /// **'Versie, bronnen en licenties'**
  String get overSamenvatting;

  /// No description provided for @dawarichAccount.
  ///
  /// In nl, this message translates to:
  /// **'Account'**
  String get dawarichAccount;

  /// No description provided for @dawarichNavigeren.
  ///
  /// In nl, this message translates to:
  /// **'Navigeren'**
  String get dawarichNavigeren;

  /// No description provided for @deelVerbinding.
  ///
  /// In nl, this message translates to:
  /// **'Verbinding'**
  String get deelVerbinding;

  /// No description provided for @deelPunten.
  ///
  /// In nl, this message translates to:
  /// **'Punten'**
  String get deelPunten;
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
