// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get appTitel => 'HomeMaps';

  @override
  String get van => 'Van';

  @override
  String get naar => 'Naar';

  @override
  String get via => 'Via';

  @override
  String get zoekPlaats => 'Zoek een plaats of adres';

  @override
  String get viaToevoegen => 'Tussenpunt toevoegen';

  @override
  String get omdraaien => 'Heen en terug omdraaien';

  @override
  String get verwijderen => 'Verwijderen';

  @override
  String get wissen => 'Route wissen';

  @override
  String get profielAuto => 'Auto';

  @override
  String get profielFiets => 'Fiets';

  @override
  String get profielLopen => 'Lopen';

  @override
  String get opties => 'Opties';

  @override
  String get liveVerkeer => 'Actueel verkeer meenemen';

  @override
  String get liveVerkeerUitleg =>
      'Files en afsluitingen van nu; alleen voor de auto';

  @override
  String get vermijdSnelwegen => 'Snelwegen vermijden';

  @override
  String get vermijdTol => 'Tolwegen vermijden';

  @override
  String get vermijdVeren => 'Veerponten vermijden';

  @override
  String get routeBezig => 'Route berekenen…';

  @override
  String get geenRoute => 'Geen route gevonden tussen deze punten.';

  @override
  String get geenWegInDeBuurt =>
      'Bij een van de punten ligt geen weg die je met dit vervoermiddel kunt gebruiken.';

  @override
  String get serverOnbereikbaar => 'De server is niet bereikbaar.';

  @override
  String get snelste => 'Snelste';

  @override
  String alternatief(int nummer) {
    return 'Alternatief $nummer';
  }

  @override
  String stijgingDaling(int stijging, int daling) {
    return '+$stijging m / -$daling m';
  }

  @override
  String get metTol => 'tol';

  @override
  String get metVeer => 'veerpont';

  @override
  String get instructies => 'Routebeschrijving';

  @override
  String get hoogteprofiel => 'Hoogteprofiel';

  @override
  String get hierVandaan => 'Route vanaf hier';

  @override
  String get hierNaartoe => 'Route hierheen';

  @override
  String get alsTussenpunt => 'Als tussenpunt';

  @override
  String get kaartstijl => 'Kaartstijl';

  @override
  String get stijlKaart => 'Kaart';

  @override
  String get stijlLicht => 'Licht';

  @override
  String get stijlDonker => 'Donker';

  @override
  String get instellingen => 'Instellingen';

  @override
  String get server => 'Server';

  @override
  String get serverUitleg =>
      'Het adres van je HomeMaps-installatie, bijvoorbeeld https://maps.example.org';

  @override
  String get serverOngeldig =>
      'Vul een adres in dat met http:// of https:// begint.';

  @override
  String get opslaan => 'Opslaan';

  @override
  String get serverNodig => 'Stel eerst het adres van je server in.';

  @override
  String get over => 'Over';

  @override
  String get overTekst =>
      'Kaart © OpenMapTiles © OpenStreetMap-bijdragers. Routes: Valhalla. Zoeken: Photon. Verkeer: NDW open data.';

  @override
  String get noordBoven => 'Noorden boven';
}
