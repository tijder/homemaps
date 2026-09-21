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
}
