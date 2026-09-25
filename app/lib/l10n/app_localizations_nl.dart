// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get appTitle => 'HomeMaps';

  @override
  String get from => 'Van';

  @override
  String get to => 'Naar';

  @override
  String get via => 'Via';

  @override
  String get searchPlace => 'Zoek een plaats of adres';

  @override
  String get addViaLabel => 'Tussenpunt toevoegen';

  @override
  String get swapEnds => 'Heen en terug omdraaien';

  @override
  String get removeLabel => 'Verwijderen';

  @override
  String get clearRoute => 'Route wissen';

  @override
  String get profileCar => 'Auto';

  @override
  String get profileBike => 'Fiets';

  @override
  String get profileWalk => 'Lopen';

  @override
  String get options => 'Opties';

  @override
  String get liveTraffic => 'Actueel verkeer meenemen';

  @override
  String get liveTrafficHelp =>
      'Files en afsluitingen van nu; alleen voor de auto';

  @override
  String get avoidMotorways => 'Snelwegen vermijden';

  @override
  String get avoidTolls => 'Tolwegen vermijden';

  @override
  String get avoidFerries => 'Veerponten vermijden';

  @override
  String get routeCalculating => 'Route berekenen…';

  @override
  String get noRoute => 'Geen route gevonden tussen deze punten.';

  @override
  String get noRoadNearby =>
      'Bij een van de punten ligt geen weg die je met dit vervoermiddel kunt gebruiken.';

  @override
  String get serverUnreachable => 'Geen HomeMaps-server gevonden op dit adres';

  @override
  String get fastest => 'Snelste';

  @override
  String alternative(int number) {
    return 'Alternatief $number';
  }

  @override
  String ascentDescent(int ascent, int descent) {
    return '+$ascent m / -$descent m';
  }

  @override
  String get withToll => 'tol';

  @override
  String get withFerry => 'veerpont';

  @override
  String get instructions => 'Routebeschrijving';

  @override
  String get elevationProfile => 'Hoogteprofiel';

  @override
  String get directionsFrom => 'Route vanaf hier';

  @override
  String get directionsTo => 'Route hierheen';

  @override
  String get asStop => 'Als tussenpunt';

  @override
  String get mapStyle => 'Kaartstijl';

  @override
  String get styleMap => 'Kaart';

  @override
  String get styleLight => 'Licht';

  @override
  String get styleDark => 'Donker';

  @override
  String get themeAutomatic => 'Automatisch';

  @override
  String get themeDay => 'Altijd dag';

  @override
  String get themeNight => 'Altijd nacht';

  @override
  String get settings => 'Instellingen';

  @override
  String get server => 'Server';

  @override
  String get serverHelp =>
      'Het adres van je HomeMaps-installatie, bijvoorbeeld https://maps.example.org';

  @override
  String get serverInvalid =>
      'Vul een webadres in, bijvoorbeeld maps.example.org.';

  @override
  String get serverChecking => 'Server controleren…';

  @override
  String get serverWorks => 'De server werkt: kaart, zoeken en routes';

  @override
  String serverPartlyWorks(String parts) {
    return 'De server antwoordt, maar niet alles werkt: $parts';
  }

  @override
  String get serverPartMap => 'kaart';

  @override
  String get serverPartSearch => 'zoeken';

  @override
  String get serverPartRoutes => 'routes';

  @override
  String get welcomeTitle => 'Welkom bij HomeMaps';

  @override
  String get welcomeText =>
      'Koppel de app eerst aan je server. Daarna kun je Dawarich koppelen en je locatie delen, of dat overslaan en later in de instellingen doen.';

  @override
  String get welcomeTextWeb =>
      'Je kunt Dawarich koppelen en je locatie delen, of dat overslaan en later in de instellingen doen.';

  @override
  String get getStarted => 'Aan de slag';

  @override
  String get next => 'Volgende';

  @override
  String get back => 'Terug';

  @override
  String get skip => 'Overslaan';

  @override
  String get skipAndStart => 'Overslaan en beginnen';

  @override
  String get toTheMap => 'Naar de kaart';

  @override
  String setupStep(int step, int total) {
    return 'Stap $step van $total';
  }

  @override
  String get setupServerIntro =>
      'Het adres van je HomeMaps-server. Zodra hij werkt, wordt hij opgeslagen.';

  @override
  String get setupDawarichIntro =>
      'Optioneel: log in bij Dawarich om je gezin op de kaart te zien en je locatiegeschiedenis bij te houden.';

  @override
  String get setupSharingIntro =>
      'Optioneel: stuur je locatie naar een eigen dienst, bijvoorbeeld OwnTracks, GeoPulse of Reitti.';

  @override
  String get save => 'Opslaan';

  @override
  String get serverRequired => 'Stel eerst het adres van je server in.';

  @override
  String get about => 'Over';

  @override
  String get northUp => 'Noorden boven';

  @override
  String get searchHere => 'Zoek op de kaart';

  @override
  String get route => 'Route';

  @override
  String get backToSearch => 'Terug naar zoeken';

  @override
  String get dragToReorder => 'Sleep om de volgorde te wijzigen';

  @override
  String get trafficOnMap => 'Verkeer';

  @override
  String get trafficRoadClosed => 'Weg afgesloten';

  @override
  String get trafficExitClosed => 'Afrit afgesloten';

  @override
  String get trafficOnRampClosed => 'Oprit afgesloten';

  @override
  String get trafficConnectingRoadClosed => 'Verbindingsweg afgesloten';

  @override
  String get trafficParallelRoadClosed => 'Parallelbaan afgesloten';

  @override
  String get trafficCarriagewayClosed => 'Rijbaan afgesloten';

  @override
  String get trafficLaneClosed => 'Rijstrook afgesloten';

  @override
  String trafficLanesOpen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rijstroken open',
      one: '1 rijstrook open',
    );
    return '$_temp0';
  }

  @override
  String get trafficJam => 'File';

  @override
  String get trafficSlow => 'Langzaam verkeer';

  @override
  String trafficDelay(String duration, int kmh) {
    return '+$duration vertraging · $kmh km/u';
  }

  @override
  String trafficUntil(String moment) {
    return 'Tot $moment';
  }

  @override
  String get causeRoadworks => 'Werkzaamheden';

  @override
  String get causeAccident => 'Ongeval';

  @override
  String get causeEvent => 'Evenement';

  @override
  String get myLocation => 'Mijn locatie';

  @override
  String get locationDenied =>
      'Zonder toestemming kan de app je locatie niet tonen.';

  @override
  String get locationNever =>
      'Locatie is voor HomeMaps geweigerd. Zet het aan in de instellingen van je telefoon.';

  @override
  String get locationNeverWeb =>
      'Locatie is voor deze site geblokkeerd. Sta het toe via het slotje naast het adres.';

  @override
  String get locationServiceOff => 'Locatie staat uit op je apparaat.';

  @override
  String get locationNotFound =>
      'Je apparaat kan je locatie niet bepalen; het blijft zoeken. Op een computer lukt dat vaak niet, op een telefoon wel.';

  @override
  String get startNavigation => 'Start';

  @override
  String navigationNotificationTitle(String destination) {
    return 'Navigatie naar $destination';
  }

  @override
  String get navigationNotificationText =>
      'HomeMaps volgt je locatie voor de route.';

  @override
  String get recalculating => 'Route wordt herberekend.';

  @override
  String get recalculatingBusy => 'Route herberekenen…';

  @override
  String fasterRoute(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other:
          'Er is een snellere route, $minutes minuten sneller. Kies op het scherm of je hem neemt.',
      one: 'Er is een snellere route, 1 minuut sneller. Kies op het scherm of je hem neemt.',
    );
    return '$_temp0';
  }

  @override
  String inDistance(String distance, String sentence) {
    return 'Over $distance $sentence';
  }

  @override
  String spokenMeters(int meter) {
    return '$meter meter';
  }

  @override
  String spokenKilometers(String km) {
    return '$km kilometer';
  }

  @override
  String get arrived => 'Je bent er';

  @override
  String get done => 'Klaar';

  @override
  String shortAction(String kind) {
    String _temp0 = intl.Intl.selectLogic(kind, {
      'onRamp': 'Oprit nemen',
      'exit': 'Afrit nemen',
      'straight': 'Rechtdoor aanhouden',
      'right': 'Rechts aanhouden',
      'left': 'Links aanhouden',
      'merge': 'Invoegen',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String exit(String number) {
    return 'Afrit $number';
  }

  @override
  String lanesAhead(String distance, String perLane) {
    return 'Over $distance: $perLane';
  }

  @override
  String lanesCorrect(int correct, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      correct,
      locale: localeName,
      other: '$correct goede rijstroken',
      one: '1 goede rijstrook',
    );
    return '$_temp0 van $total';
  }

  @override
  String get resume => 'Hervatten';

  @override
  String get stopNavigation => 'Stop';

  @override
  String get voiceOff => 'Stem uit';

  @override
  String get voiceOn => 'Stem aan';

  @override
  String arrival(String time) {
    return 'Aankomst $time';
  }

  @override
  String get afterwards => 'Daarna';

  @override
  String get locationSearching => 'Locatie zoeken…';

  @override
  String get locationEnableToNavigate => 'Locatie aanzetten om te navigeren';

  @override
  String get navigatingWithoutLocation =>
      'Navigeren kan pas als je locatie bekend is.';

  @override
  String get tryAgain => 'Opnieuw proberen';

  @override
  String stopCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'via $count tussenpunten',
      one: 'via 1 tussenpunt',
    );
    return '$_temp0';
  }

  @override
  String get editRoute => 'Route wijzigen';

  @override
  String get stopFirst => 'Stop eerst de navigatie.';

  @override
  String get delay => 'vertraging';

  @override
  String suggestionFaster(int minutes) {
    return 'Snellere route: $minutes min sneller';
  }

  @override
  String suggestionVia(String road) {
    return 'via $road';
  }

  @override
  String get accept => 'Nemen';

  @override
  String get ignore => 'Negeren';

  @override
  String arrivalAt(String time) {
    return 'aankomst $time';
  }

  @override
  String get home => 'Thuis';

  @override
  String get work => 'Werk';

  @override
  String get asHome => 'Als thuis';

  @override
  String get asWork => 'Als werk';

  @override
  String get savedPlaces => 'Plekken';

  @override
  String get savedPlacesHelp =>
      'Thuis en werk stel je in op het kaartje van een gevonden plek.';

  @override
  String get notSet => 'Niet ingesteld';

  @override
  String get recentPlaces => 'Recente plekken';

  @override
  String savedPlaceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plekken',
      one: '1 plek',
      zero: 'Geen',
    );
    return '$_temp0';
  }

  @override
  String get clearLabel => 'Wissen';

  @override
  String notFound(String search) {
    return 'Niet gevonden: $search';
  }

  @override
  String get kmh => 'km/u';

  @override
  String speedLimit(int kmh) {
    return 'Maximumsnelheid $kmh km/u';
  }

  @override
  String speedLimitTemporary(int kmh) {
    return 'Tijdelijke maximumsnelheid $kmh km/u';
  }

  @override
  String speedLimitMatrix(int kmh) {
    return 'Maximumsnelheid $kmh km/u op de matrixborden';
  }

  @override
  String get incidentAccident => 'Ongeval';

  @override
  String get incidentBreakdown => 'Pechgeval';

  @override
  String get incidentObstacle => 'Voorwerp op de weg';

  @override
  String get incidentBridge => 'Open brug';

  @override
  String get matrixSigns => 'Matrixborden';

  @override
  String incidentSince(String time) {
    return 'Sinds $time';
  }

  @override
  String warningOnRoute(String notification, String distance) {
    return 'Let op: $notification over $distance.';
  }

  @override
  String get departure => 'Vertrek';

  @override
  String get departNow => 'Nu';

  @override
  String get departLater => 'Later…';

  @override
  String closureOnRoute(String window, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count geplande afsluitingen op deze route, de eerste: $window',
      one: 'Geplande afsluiting op deze route: $window',
    );
    return '$_temp0';
  }

  @override
  String get alongTheRoute => 'Langs de route';

  @override
  String get alongFuel => 'Tanken';

  @override
  String get alongCharging => 'Laden';

  @override
  String get alongSupermarket => 'Supermarkt';

  @override
  String get alongFood => 'Eten';

  @override
  String get alongNothing =>
      'Niets gevonden binnen een kilometer van de route.';

  @override
  String alongDistance(String distance) {
    return '$distance van de route';
  }

  @override
  String stopAdded(String label) {
    return 'Tussenstop: $label';
  }

  @override
  String get locationSharing => 'Locatie delen';

  @override
  String get locationSharingHelp =>
      'Stuur je positie naar je eigen server, zoals Colota dat doet. Alleen tijdens het navigeren.';

  @override
  String get locationSharingEnabled => 'Delen tijdens navigeren';

  @override
  String get shareOff => 'Uit';

  @override
  String get shareServer => 'Server';

  @override
  String get shareCustom => 'Eigen server';

  @override
  String shareTemplateHelp(String template) {
    String _temp0 = intl.Intl.selectLogic(template, {
      'dawarich':
          'Dawarich-API: punten in batches, met richting, batterij en vervoer',
      'geopulse': 'Colota-formaat voor GeoPulse',
      'overland': 'Overland: punten in batches (GeoJSON)',
      'owntracks': 'Standaard OwnTracks over HTTP',
      'phonetrack': 'Nextcloud PhoneTrack',
      'reitti': 'OwnTracks-formaat voor Reitti',
      'traccar': 'Traccar, OsmAnd-protocol',
      'other': 'Je eigen veldnamen',
    });
    return '$_temp0';
  }

  @override
  String get shareUrl => 'Adres (URL)';

  @override
  String get shareUrlInvalid =>
      'Vul een adres in dat met http:// of https:// begint.';

  @override
  String get shareUrlWeb => 'In de browser moet de server CORS toestaan.';

  @override
  String get shareMethod => 'Methode';

  @override
  String get shareAuth => 'Inloggen';

  @override
  String get shareAuthNone => 'Geen';

  @override
  String get shareUsername => 'Gebruikersnaam';

  @override
  String get sharePassword => 'Wachtwoord';

  @override
  String get shareToken => 'Token';

  @override
  String get shareFieldNames => 'Veldnamen';

  @override
  String get shareFieldNamesHelp =>
      'Per regel veld=naam, bijvoorbeeld lat=latitude. Velden: lat, lon, acc, alt, vel, tst, bear.';

  @override
  String get shareExtraFields => 'Vaste velden';

  @override
  String get shareExtraFieldsHelp =>
      'Per regel naam=waarde; die gaan bij elk punt mee.';

  @override
  String get shareInterval => 'Elke … seconden';

  @override
  String get shareMinDistance => 'Of na … meter';

  @override
  String get shareTest => 'Verbinding testen';

  @override
  String get shareTestSucceeded => 'De server heeft het punt ontvangen.';

  @override
  String shareTestFailed(String error) {
    return 'Niet gelukt: $error';
  }

  @override
  String get shareStatus => 'Status';

  @override
  String shareLastSent(String time) {
    return 'Laatst verstuurd om $time';
  }

  @override
  String get shareNothingYet => 'Nog niets verstuurd';

  @override
  String shareQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count punten in de wachtrij',
      one: '1 punt in de wachtrij',
      zero: 'Niets in de wachtrij',
    );
    return '$_temp0';
  }

  @override
  String shareError(String error) {
    return 'Fout: $error';
  }

  @override
  String get shareStopped => 'Gestopt tot je de instellingen wijzigt.';

  @override
  String get shareClearQueue => 'Wachtrij leegmaken';

  @override
  String get shareExample => 'Voorbeeld';

  @override
  String get navigationNotificationSharing =>
      'HomeMaps volgt je locatie voor de route en deelt hem met je server.';

  @override
  String get aboutHomeMaps => 'Over HomeMaps';

  @override
  String version(String version) {
    return 'Versie $version';
  }

  @override
  String get aboutDescription =>
      'Navigatie op je eigen server: kaart, routes, zoeken en verkeer.';

  @override
  String get sources => 'Gegevens en software';

  @override
  String get sourceMapData => 'Kaartgegevens © OpenStreetMap-bijdragers';

  @override
  String get sourceTiles => 'Kaarttegels en -stijl';

  @override
  String get sourceRouting => 'Routes en navigatie';

  @override
  String get sourceSearch => 'Zoeken';

  @override
  String get sourceTraffic => 'Verkeer, werk en matrixborden';

  @override
  String get sourceCode => 'Broncode';

  @override
  String get licenses => 'Licenties';

  @override
  String get saveLog => 'Log opslaan';

  @override
  String get saveLogSubtitle =>
      'Sla het app-log op als bestand voor probleemonderzoek';

  @override
  String get logSaved => 'Log opgeslagen';

  @override
  String logSaveFailed(String error) {
    return 'Log opslaan mislukt: $error';
  }

  @override
  String get logEmpty => 'Er is nog geen log om op te slaan';

  @override
  String get dawarich => 'Dawarich';

  @override
  String get dawarichHelp =>
      'Vul het adres van je eigen Dawarich in. Daarna log je in, en kun je je locatie met je familie delen, onderweg je rit bijhouden en familieleden op de kaart zien.';

  @override
  String get dawarichNotSignedIn => 'Niet ingelogd';

  @override
  String get dawarichServer => 'Server';

  @override
  String get dawarichWithKey => 'Met een API-sleutel';

  @override
  String get dawarichEmail => 'E-mail';

  @override
  String get dawarichPassword => 'Wachtwoord';

  @override
  String get dawarichKey => 'API-sleutel';

  @override
  String get dawarichKeyHelp => 'Te vinden in Dawarich onder Instellingen.';

  @override
  String get dawarichSignIn => 'Inloggen';

  @override
  String get dawarichSignOut => 'Uitloggen';

  @override
  String get dawarichCode => 'Code voor tweestapsverificatie';

  @override
  String get dawarichCodeHelp =>
      'De code uit je authenticator-app, of een back-upcode.';

  @override
  String get dawarichConfirm => 'Bevestigen';

  @override
  String get cancelLabel => 'Annuleren';

  @override
  String get dawarichErrorCredentials => 'Onjuiste gegevens.';

  @override
  String get dawarichErrorPasswordDisabled =>
      'Deze server staat inloggen met een wachtwoord niet toe. Gebruik een API-sleutel.';

  @override
  String get dawarichErrorBlocked =>
      'Te vaak een verkeerde code. Probeer het later opnieuw.';

  @override
  String dawarichErrorConnection(String detail) {
    return 'Dawarich is niet te bereiken ($detail).';
  }

  @override
  String dawarichErrorUnknown(String detail) {
    return 'Er ging iets mis ($detail).';
  }

  @override
  String dawarichSignedInAs(String email) {
    return 'Ingelogd als $email';
  }

  @override
  String get dawarichFamily => 'Familie';

  @override
  String get dawarichShareWithFamily => 'Locatie delen met familie';

  @override
  String dawarichSharingUntil(String time) {
    return 'Tot $time';
  }

  @override
  String get dawarichSharingAlways => 'Tot je het uitzet';

  @override
  String get dawarichNotSharing => 'Je familie ziet je locatie niet';

  @override
  String get dawarichNoFamily =>
      'Je zit nog niet in een familie. Maak er een of word lid op de Dawarich-website.';

  @override
  String get dawarichOpenWebsite => 'Naar de website';

  @override
  String get dawarichNoSubscription =>
      'Familie zit niet in je Dawarich-abonnement.';

  @override
  String get dawarichHowLong => 'Hoe lang delen?';

  @override
  String dawarichDuration(String duration) {
    String _temp0 = intl.Intl.selectLogic(duration, {
      'hour1': '1 uur',
      'hour6': '6 uur',
      'hour12': '12 uur',
      'hour24': '24 uur',
      'other': 'Tot ik het uitzet',
    });
    return '$_temp0';
  }

  @override
  String get dawarichShareEnRoute => 'Locatie delen tijdens navigeren';

  @override
  String get dawarichShareEnRouteHelp =>
      'Stuurt je rit naar Dawarich. Interval en afstand stel je in bij Locatie delen.';

  @override
  String get dawarichShowFamily => 'Familieleden op de kaart';

  @override
  String get dawarichShowFamilyHelp =>
      'Elke 30 seconden bijgewerkt, zolang de app open is.';

  @override
  String get dawarichFamilySharing => 'familie deelt';

  @override
  String get shareViaDawarich => 'Ingesteld via je Dawarich-account.';

  @override
  String familyMinutesAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minuten geleden',
      one: '1 minuut geleden',
      zero: 'zojuist',
    );
    return '$_temp0';
  }

  @override
  String familyBattery(int percent) {
    return 'batterij $percent%';
  }

  @override
  String familyHoursAgo(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours uur geleden',
      one: '1 uur geleden',
    );
    return '$_temp0';
  }

  @override
  String familyDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days dagen geleden',
      one: '1 dag geleden',
    );
    return '$_temp0';
  }

  @override
  String get familyFollow => 'Volgen';

  @override
  String get familyFollowing => 'Wordt gevolgd';

  @override
  String get settingsGroupMap => 'Kaart en route';

  @override
  String get settingsGroupSharing => 'Delen';

  @override
  String get settingsGroupApp => 'App';

  @override
  String get settingsMap => 'Kaart';

  @override
  String get dayAndNight => 'Dag en nacht';

  @override
  String get themeOnlyMap =>
      'Alleen bij de stijl Kaart; Licht en Donker zijn al een keuze.';

  @override
  String get layers => 'Lagen';

  @override
  String get trafficOnMapHelp =>
      'Afsluitingen, werk op de weg en files op de kaart';

  @override
  String get transport => 'Vervoer';

  @override
  String get transportHelp => 'Waarmee een nieuwe route berekend wordt.';

  @override
  String get saved => 'Opgeslagen';

  @override
  String get aboutSummary => 'Versie, bronnen en licenties';

  @override
  String get dawarichAccount => 'Account';

  @override
  String get dawarichNavigation => 'Navigeren';

  @override
  String get shareConnection => 'Verbinding';

  @override
  String get sharePoints => 'Punten';

  @override
  String get dawarichWebsiteHelp =>
      'Ook voor OIDC, zoals Keycloak of Authentik. Niet met Google.';

  @override
  String get dawarichWebsiteSignIn => 'Via de Dawarich-website';

  @override
  String get dawarichWebsiteTitle => 'Inloggen bij Dawarich';

  @override
  String dawarichWebsiteError(String error) {
    return 'De pagina laadt niet: $error';
  }

  @override
  String get dawarichErrorCors =>
      'Dawarich is niet te bereiken vanuit de browser. Dawarich staat dat zelf niet toe (CORS); voeg in je reverse proxy CORS-headers toe voor /api/v1, of gebruik de Android-app.';

  @override
  String get dawarichErrorNotDawarich =>
      'Op dit adres antwoordt geen Dawarich. Staat er een inlogproxy voor (zoals Authelia), laat dan /api/v1 door.';

  @override
  String get dawarichStepServer => 'Server';

  @override
  String get dawarichConnect => 'Verbinden';

  @override
  String get dawarichConnected => 'Verbonden';

  @override
  String dawarichConnectedVersion(String version) {
    return 'Verbonden · Dawarich $version';
  }

  @override
  String get dawarichChange => 'Wijzigen';

  @override
  String get dawarichStepSignIn => 'Inloggen';

  @override
  String get dawarichOtherWays => 'Andere manieren';

  @override
  String get dawarichSignOutQuestion => 'Uitloggen bij Dawarich?';

  @override
  String get dawarichSignOutHelp =>
      'Delen tijdens het navigeren stopt, en de familie verdwijnt van de kaart.';

  @override
  String get dawarichChecking => 'Verbinding controleren…';

  @override
  String get dawarichSessionExpired => 'Sessie verlopen';

  @override
  String get dawarichSessionExpiredHelp =>
      'Je API-sleutel werkt niet meer. Log opnieuw in.';

  @override
  String get dawarichUnreachable => 'Niet bereikbaar';

  @override
  String get dawarichSignInAgain => 'Opnieuw inloggen';

  @override
  String get carWhereTo => 'Waarheen?';

  @override
  String get carOpenApp => 'Open HomeMaps op je telefoon en zet locatie aan.';

  @override
  String get carNoResults => 'Niets gevonden.';

  @override
  String get carRoutes => 'Routes';
}
