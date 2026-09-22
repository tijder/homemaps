// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitel => 'HomeMaps';

  @override
  String get van => 'From';

  @override
  String get naar => 'To';

  @override
  String get via => 'Via';

  @override
  String get zoekPlaats => 'Search a place or address';

  @override
  String get viaToevoegen => 'Add stop';

  @override
  String get omdraaien => 'Swap start and destination';

  @override
  String get verwijderen => 'Remove';

  @override
  String get wissen => 'Clear route';

  @override
  String get profielAuto => 'Car';

  @override
  String get profielFiets => 'Bike';

  @override
  String get profielLopen => 'Walk';

  @override
  String get opties => 'Options';

  @override
  String get liveVerkeer => 'Use live traffic';

  @override
  String get liveVerkeerUitleg => 'Current congestion and closures; car only';

  @override
  String get vermijdSnelwegen => 'Avoid motorways';

  @override
  String get vermijdTol => 'Avoid toll roads';

  @override
  String get vermijdVeren => 'Avoid ferries';

  @override
  String get routeBezig => 'Calculating route…';

  @override
  String get geenRoute => 'No route found between these points.';

  @override
  String get geenWegInDeBuurt =>
      'There is no road near one of the points that this mode of travel can use.';

  @override
  String get serverOnbereikbaar => 'The server cannot be reached.';

  @override
  String get snelste => 'Fastest';

  @override
  String alternatief(int nummer) {
    return 'Alternative $nummer';
  }

  @override
  String stijgingDaling(int stijging, int daling) {
    return '+$stijging m / -$daling m';
  }

  @override
  String get metTol => 'toll';

  @override
  String get metVeer => 'ferry';

  @override
  String get instructies => 'Directions';

  @override
  String get hoogteprofiel => 'Elevation profile';

  @override
  String get hierVandaan => 'Directions from here';

  @override
  String get hierNaartoe => 'Directions to here';

  @override
  String get alsTussenpunt => 'Add as stop';

  @override
  String get kaartstijl => 'Map style';

  @override
  String get stijlKaart => 'Map';

  @override
  String get stijlLicht => 'Light';

  @override
  String get stijlDonker => 'Dark';

  @override
  String get instellingen => 'Settings';

  @override
  String get server => 'Server';

  @override
  String get serverUitleg =>
      'The address of your HomeMaps installation, for example https://maps.example.org';

  @override
  String get serverOngeldig =>
      'Enter an address starting with http:// or https://.';

  @override
  String get opslaan => 'Save';

  @override
  String get serverNodig => 'Set the address of your server first.';

  @override
  String get over => 'About';

  @override
  String get overTekst =>
      'Map © OpenMapTiles © OpenStreetMap contributors. Routing: Valhalla. Search: Photon. Traffic: NDW open data.';

  @override
  String get noordBoven => 'North up';

  @override
  String get zoekHier => 'Search the map';

  @override
  String get route => 'Directions';

  @override
  String get terugNaarZoeken => 'Back to search';

  @override
  String get sleepOmTeVerplaatsen => 'Drag to reorder';

  @override
  String get verkeerOpKaart => 'Traffic';

  @override
  String get verkeerWegDicht => 'Road closed';

  @override
  String get verkeerAfritDicht => 'Exit closed';

  @override
  String get verkeerOpritDicht => 'On-ramp closed';

  @override
  String get verkeerVerbindingswegDicht => 'Connecting road closed';

  @override
  String get verkeerParallelbaanDicht => 'Parallel road closed';

  @override
  String get verkeerRijbaanDicht => 'Carriageway closed';

  @override
  String get verkeerRijstrookDicht => 'Lane closed';

  @override
  String verkeerStrokenOpen(int aantal) {
    String _temp0 = intl.Intl.pluralLogic(
      aantal,
      locale: localeName,
      other: '$aantal lanes open',
      one: '1 lane open',
    );
    return '$_temp0';
  }

  @override
  String get verkeerFile => 'Traffic jam';

  @override
  String get verkeerTraag => 'Slow traffic';

  @override
  String verkeerVertraging(String duur, int kmu) {
    return '+$duur delay · $kmu km/h';
  }

  @override
  String verkeerTot(String moment) {
    return 'Until $moment';
  }

  @override
  String get oorzaakWerk => 'Roadworks';

  @override
  String get oorzaakOngeval => 'Accident';

  @override
  String get oorzaakEvenement => 'Event';

  @override
  String get mijnLocatie => 'My location';

  @override
  String get locatieGeweigerd =>
      'Without permission the app can\'t show your location.';

  @override
  String get locatieNooit =>
      'Location is denied for HomeMaps. Turn it on in your phone\'s settings.';

  @override
  String get locatieNooitWeb =>
      'Location is blocked for this site. Allow it via the padlock next to the address.';

  @override
  String get locatieDienstUit => 'Location is turned off on your device.';

  @override
  String get locatieNietGevonden =>
      'Your device can\'t determine your location; it keeps trying. Computers often can\'t, phones can.';

  @override
  String get startNavigatie => 'Start';

  @override
  String navigatieMeldingTitel(String bestemming) {
    return 'Navigating to $bestemming';
  }

  @override
  String get navigatieMeldingTekst =>
      'HomeMaps is following your location for directions.';

  @override
  String get herberekenen => 'Recalculating route.';

  @override
  String get herberekenenBezig => 'Recalculating…';

  @override
  String snellereRoute(int minuten) {
    String _temp0 = intl.Intl.pluralLogic(
      minuten,
      locale: localeName,
      other:
          'There is a faster route, $minuten minutes faster. Choose on screen whether to take it.',
      one: 'There is a faster route, 1 minute faster. Choose on screen whether to take it.',
    );
    return '$_temp0';
  }

  @override
  String overAfstand(String afstand, String zin) {
    return 'In $afstand, $zin';
  }

  @override
  String gesprokenMeter(int meter) {
    return '$meter meters';
  }

  @override
  String gesprokenKilometer(String km) {
    return '$km kilometers';
  }

  @override
  String get aangekomen => 'You have arrived';

  @override
  String get klaar => 'Done';

  @override
  String get hervatten => 'Re-centre';

  @override
  String get stopNavigatie => 'Stop';

  @override
  String get stemUit => 'Mute';

  @override
  String get stemAan => 'Unmute';

  @override
  String aankomst(String tijd) {
    return 'Arrive $tijd';
  }

  @override
  String get daarna => 'Then';

  @override
  String get locatieZoeken => 'Finding location…';

  @override
  String get locatieAanOmTeNavigeren => 'Turn on location to navigate';

  @override
  String get navigerenZonderLocatie => 'Navigation needs your location.';

  @override
  String get opnieuwProberen => 'Try again';

  @override
  String aantalTussenpunten(int aantal) {
    String _temp0 = intl.Intl.pluralLogic(
      aantal,
      locale: localeName,
      other: 'via $aantal stops',
      one: 'via 1 stop',
    );
    return '$_temp0';
  }

  @override
  String get routeWijzigen => 'Edit route';

  @override
  String get eerstStoppen => 'Stop navigation first.';

  @override
  String get vertraging => 'delay';

  @override
  String voorstelSneller(int minuten) {
    return 'Faster route: $minuten min faster';
  }

  @override
  String voorstelVia(String weg) {
    return 'via $weg';
  }

  @override
  String get nemen => 'Take it';

  @override
  String get negeren => 'Ignore';

  @override
  String aankomstOm(String tijd) {
    return 'arrive $tijd';
  }

  @override
  String get thuis => 'Home';

  @override
  String get werk => 'Work';

  @override
  String get alsThuis => 'Set as home';

  @override
  String get alsWerk => 'Set as work';

  @override
  String get plekken => 'Places';

  @override
  String get plekkenUitleg =>
      'Set home and work on the card of a place you found.';

  @override
  String get nietIngesteld => 'Not set';

  @override
  String get recentePlekken => 'Recent places';

  @override
  String aantalPlekken(int aantal) {
    String _temp0 = intl.Intl.pluralLogic(
      aantal,
      locale: localeName,
      other: '$aantal places',
      one: '1 place',
      zero: 'None',
    );
    return '$_temp0';
  }

  @override
  String get wissenKort => 'Clear';

  @override
  String nietGevonden(String zoek) {
    return 'Not found: $zoek';
  }

  @override
  String get kmu => 'km/h';

  @override
  String maximumsnelheid(int kmu) {
    return 'Speed limit $kmu km/h';
  }

  @override
  String get meldingOngeval => 'Accident';

  @override
  String get meldingPech => 'Broken-down vehicle';

  @override
  String get meldingObstakel => 'Object on the road';

  @override
  String meldingSinds(String tijd) {
    return 'Since $tijd';
  }

  @override
  String waarschuwingOpRoute(String melding, String afstand) {
    return 'Caution: $melding in $afstand.';
  }

  @override
  String get vertrek => 'Depart';

  @override
  String get vertrekNu => 'Now';

  @override
  String get vertrekLater => 'Later…';

  @override
  String afsluitingOpRoute(String venster, int aantal) {
    String _temp0 = intl.Intl.pluralLogic(
      aantal,
      locale: localeName,
      other: '$aantal planned closures on this route, first: $venster',
      one: 'Planned closure on this route: $venster',
    );
    return '$_temp0';
  }

  @override
  String get langsDeRoute => 'Along the route';

  @override
  String get langsTanken => 'Fuel';

  @override
  String get langsLaden => 'Charging';

  @override
  String get langsSupermarkt => 'Supermarket';

  @override
  String get langsEten => 'Food';

  @override
  String get langsNiets => 'Nothing found within a kilometre of the route.';

  @override
  String langsAfstand(String afstand) {
    return '$afstand from the route';
  }

  @override
  String tussenstopToegevoegd(String naam) {
    return 'Stop: $naam';
  }
}
