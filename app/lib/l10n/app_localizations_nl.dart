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

  @override
  String get zoekHier => 'Zoek op de kaart';

  @override
  String get route => 'Route';

  @override
  String get terugNaarZoeken => 'Terug naar zoeken';

  @override
  String get sleepOmTeVerplaatsen => 'Sleep om de volgorde te wijzigen';

  @override
  String get verkeerOpKaart => 'Verkeer';

  @override
  String get verkeerWegDicht => 'Weg afgesloten';

  @override
  String get verkeerAfritDicht => 'Afrit afgesloten';

  @override
  String get verkeerOpritDicht => 'Oprit afgesloten';

  @override
  String get verkeerVerbindingswegDicht => 'Verbindingsweg afgesloten';

  @override
  String get verkeerParallelbaanDicht => 'Parallelbaan afgesloten';

  @override
  String get verkeerRijbaanDicht => 'Rijbaan afgesloten';

  @override
  String get verkeerRijstrookDicht => 'Rijstrook afgesloten';

  @override
  String verkeerStrokenOpen(int aantal) {
    String _temp0 = intl.Intl.pluralLogic(
      aantal,
      locale: localeName,
      other: '$aantal rijstroken open',
      one: '1 rijstrook open',
    );
    return '$_temp0';
  }

  @override
  String get verkeerFile => 'File';

  @override
  String get verkeerTraag => 'Langzaam verkeer';

  @override
  String verkeerVertraging(String duur, int kmu) {
    return '+$duur vertraging · $kmu km/u';
  }

  @override
  String verkeerTot(String moment) {
    return 'Tot $moment';
  }

  @override
  String get oorzaakWerk => 'Werkzaamheden';

  @override
  String get oorzaakOngeval => 'Ongeval';

  @override
  String get oorzaakEvenement => 'Evenement';

  @override
  String get mijnLocatie => 'Mijn locatie';

  @override
  String get locatieGeweigerd =>
      'Zonder toestemming kan de app je locatie niet tonen.';

  @override
  String get locatieNooit =>
      'Locatie is voor HomeMaps geweigerd. Zet het aan in de instellingen van je telefoon.';

  @override
  String get locatieNooitWeb =>
      'Locatie is voor deze site geblokkeerd. Sta het toe via het slotje naast het adres.';

  @override
  String get locatieDienstUit => 'Locatie staat uit op je apparaat.';

  @override
  String get locatieNietGevonden =>
      'Je apparaat kan je locatie niet bepalen; het blijft zoeken. Op een computer lukt dat vaak niet, op een telefoon wel.';

  @override
  String get startNavigatie => 'Start';

  @override
  String navigatieMeldingTitel(String bestemming) {
    return 'Navigatie naar $bestemming';
  }

  @override
  String get navigatieMeldingTekst =>
      'HomeMaps volgt je locatie voor de route.';

  @override
  String get herberekenen => 'Route wordt herberekend.';

  @override
  String get herberekenenBezig => 'Route herberekenen…';

  @override
  String snellereRoute(int minuten) {
    String _temp0 = intl.Intl.pluralLogic(
      minuten,
      locale: localeName,
      other:
          'Er is een snellere route, $minuten minuten sneller. Kies op het scherm of je hem neemt.',
      one: 'Er is een snellere route, 1 minuut sneller. Kies op het scherm of je hem neemt.',
    );
    return '$_temp0';
  }

  @override
  String overAfstand(String afstand, String zin) {
    return 'Over $afstand $zin';
  }

  @override
  String gesprokenMeter(int meter) {
    return '$meter meter';
  }

  @override
  String gesprokenKilometer(String km) {
    return '$km kilometer';
  }

  @override
  String get aangekomen => 'Je bent er';

  @override
  String get klaar => 'Klaar';

  @override
  String afrit(String nummer) {
    return 'Afrit $nummer';
  }

  @override
  String rijstrokenGoed(int goed, int totaal) {
    String _temp0 = intl.Intl.pluralLogic(
      goed,
      locale: localeName,
      other: '$goed goede rijstroken',
      one: '1 goede rijstrook',
    );
    return '$_temp0 van $totaal';
  }

  @override
  String get hervatten => 'Hervatten';

  @override
  String get stopNavigatie => 'Stop';

  @override
  String get stemUit => 'Stem uit';

  @override
  String get stemAan => 'Stem aan';

  @override
  String aankomst(String tijd) {
    return 'Aankomst $tijd';
  }

  @override
  String get daarna => 'Daarna';

  @override
  String get locatieZoeken => 'Locatie zoeken…';

  @override
  String get locatieAanOmTeNavigeren => 'Locatie aanzetten om te navigeren';

  @override
  String get navigerenZonderLocatie =>
      'Navigeren kan pas als je locatie bekend is.';

  @override
  String get opnieuwProberen => 'Opnieuw proberen';

  @override
  String aantalTussenpunten(int aantal) {
    String _temp0 = intl.Intl.pluralLogic(
      aantal,
      locale: localeName,
      other: 'via $aantal tussenpunten',
      one: 'via 1 tussenpunt',
    );
    return '$_temp0';
  }

  @override
  String get routeWijzigen => 'Route wijzigen';

  @override
  String get eerstStoppen => 'Stop eerst de navigatie.';

  @override
  String get vertraging => 'vertraging';

  @override
  String voorstelSneller(int minuten) {
    return 'Snellere route: $minuten min sneller';
  }

  @override
  String voorstelVia(String weg) {
    return 'via $weg';
  }

  @override
  String get nemen => 'Nemen';

  @override
  String get negeren => 'Negeren';

  @override
  String aankomstOm(String tijd) {
    return 'aankomst $tijd';
  }

  @override
  String get thuis => 'Thuis';

  @override
  String get werk => 'Werk';

  @override
  String get alsThuis => 'Als thuis';

  @override
  String get alsWerk => 'Als werk';

  @override
  String get plekken => 'Plekken';

  @override
  String get plekkenUitleg =>
      'Thuis en werk stel je in op het kaartje van een gevonden plek.';

  @override
  String get nietIngesteld => 'Niet ingesteld';

  @override
  String get recentePlekken => 'Recente plekken';

  @override
  String aantalPlekken(int aantal) {
    String _temp0 = intl.Intl.pluralLogic(
      aantal,
      locale: localeName,
      other: '$aantal plekken',
      one: '1 plek',
      zero: 'Geen',
    );
    return '$_temp0';
  }

  @override
  String get wissenKort => 'Wissen';

  @override
  String nietGevonden(String zoek) {
    return 'Niet gevonden: $zoek';
  }

  @override
  String get kmu => 'km/u';

  @override
  String maximumsnelheid(int kmu) {
    return 'Maximumsnelheid $kmu km/u';
  }

  @override
  String maximumsnelheidTijdelijk(int kmu) {
    return 'Tijdelijke maximumsnelheid $kmu km/u';
  }

  @override
  String maximumsnelheidMatrix(int kmu) {
    return 'Maximumsnelheid $kmu km/u op de matrixborden';
  }

  @override
  String get meldingOngeval => 'Ongeval';

  @override
  String get meldingPech => 'Pechgeval';

  @override
  String get meldingObstakel => 'Voorwerp op de weg';

  @override
  String get meldingBrug => 'Open brug';

  @override
  String get matrixborden => 'Matrixborden';

  @override
  String meldingSinds(String tijd) {
    return 'Sinds $tijd';
  }

  @override
  String waarschuwingOpRoute(String melding, String afstand) {
    return 'Let op: $melding over $afstand.';
  }

  @override
  String get vertrek => 'Vertrek';

  @override
  String get vertrekNu => 'Nu';

  @override
  String get vertrekLater => 'Later…';

  @override
  String afsluitingOpRoute(String venster, int aantal) {
    String _temp0 = intl.Intl.pluralLogic(
      aantal,
      locale: localeName,
      other: '$aantal geplande afsluitingen op deze route, de eerste: $venster',
      one: 'Geplande afsluiting op deze route: $venster',
    );
    return '$_temp0';
  }

  @override
  String get langsDeRoute => 'Langs de route';

  @override
  String get langsTanken => 'Tanken';

  @override
  String get langsLaden => 'Laden';

  @override
  String get langsSupermarkt => 'Supermarkt';

  @override
  String get langsEten => 'Eten';

  @override
  String get langsNiets => 'Niets gevonden binnen een kilometer van de route.';

  @override
  String langsAfstand(String afstand) {
    return '$afstand van de route';
  }

  @override
  String tussenstopToegevoegd(String naam) {
    return 'Tussenstop: $naam';
  }
}
