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
  String get themaAutomatisch => 'Automatisch';

  @override
  String get themaDag => 'Altijd dag';

  @override
  String get themaNacht => 'Altijd nacht';

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
  String korteActie(String soort) {
    String _temp0 = intl.Intl.selectLogic(soort, {
      'oprit': 'Oprit nemen',
      'afrit': 'Afrit nemen',
      'rechtdoor': 'Rechtdoor aanhouden',
      'rechts': 'Rechts aanhouden',
      'links': 'Links aanhouden',
      'invoegen': 'Invoegen',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String afrit(String nummer) {
    return 'Afrit $nummer';
  }

  @override
  String rijstrokenOver(String afstand, String stroken) {
    return 'Over $afstand: $stroken';
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

  @override
  String get locatieDelen => 'Locatie delen';

  @override
  String get locatieDelenUitleg =>
      'Stuur je positie naar je eigen server, zoals Colota dat doet. Alleen tijdens het navigeren.';

  @override
  String get locatieDelenAan => 'Delen tijdens navigeren';

  @override
  String get deelUit => 'Uit';

  @override
  String get deelServer => 'Server';

  @override
  String get deelAangepast => 'Eigen server';

  @override
  String deelSjabloonUitleg(String sjabloon) {
    String _temp0 = intl.Intl.selectLogic(sjabloon, {
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
  String get deelUrl => 'Adres (URL)';

  @override
  String get deelUrlOngeldig =>
      'Vul een adres in dat met http:// of https:// begint.';

  @override
  String get deelUrlWeb => 'In de browser moet de server CORS toestaan.';

  @override
  String get deelMethode => 'Methode';

  @override
  String get deelInlog => 'Inloggen';

  @override
  String get deelInlogGeen => 'Geen';

  @override
  String get deelGebruiker => 'Gebruikersnaam';

  @override
  String get deelWachtwoord => 'Wachtwoord';

  @override
  String get deelToken => 'Token';

  @override
  String get deelVeldnamen => 'Veldnamen';

  @override
  String get deelVeldnamenUitleg =>
      'Per regel veld=naam, bijvoorbeeld lat=latitude. Velden: lat, lon, acc, alt, vel, tst, bear.';

  @override
  String get deelExtraVelden => 'Vaste velden';

  @override
  String get deelExtraVeldenUitleg =>
      'Per regel naam=waarde; die gaan bij elk punt mee.';

  @override
  String get deelInterval => 'Elke … seconden';

  @override
  String get deelMinAfstand => 'Of na … meter';

  @override
  String get deelTesten => 'Verbinding testen';

  @override
  String get deelTestGelukt => 'De server heeft het punt ontvangen.';

  @override
  String deelTestMislukt(String fout) {
    return 'Niet gelukt: $fout';
  }

  @override
  String get deelStatus => 'Status';

  @override
  String deelLaatst(String tijd) {
    return 'Laatst verstuurd om $tijd';
  }

  @override
  String get deelNogNiets => 'Nog niets verstuurd';

  @override
  String deelInWachtrij(int aantal) {
    String _temp0 = intl.Intl.pluralLogic(
      aantal,
      locale: localeName,
      other: '$aantal punten in de wachtrij',
      one: '1 punt in de wachtrij',
      zero: 'Niets in de wachtrij',
    );
    return '$_temp0';
  }

  @override
  String deelFout(String fout) {
    return 'Fout: $fout';
  }

  @override
  String get deelGestopt => 'Gestopt tot je de instellingen wijzigt.';

  @override
  String get deelWisWachtrij => 'Wachtrij leegmaken';

  @override
  String get deelVoorbeeld => 'Voorbeeld';

  @override
  String get navigatieMeldingDelen =>
      'HomeMaps volgt je locatie voor de route en deelt hem met je server.';

  @override
  String get overHomeMaps => 'Over HomeMaps';

  @override
  String versie(String versie) {
    return 'Versie $versie';
  }

  @override
  String get overBeschrijving =>
      'Navigatie op je eigen server: kaart, routes, zoeken en verkeer.';

  @override
  String get bronnen => 'Gegevens en software';

  @override
  String get bronKaartgegevens => 'Kaartgegevens © OpenStreetMap-bijdragers';

  @override
  String get bronTegels => 'Kaarttegels en -stijl';

  @override
  String get bronRoutes => 'Routes en navigatie';

  @override
  String get bronZoeken => 'Zoeken';

  @override
  String get bronVerkeer => 'Verkeer, werk en matrixborden';

  @override
  String get broncode => 'Broncode';

  @override
  String get licenties => 'Licenties';

  @override
  String get dawarich => 'Dawarich';

  @override
  String get dawarichUitleg =>
      'Log in bij je eigen Dawarich-server om je locatie met je familie te delen, onderweg je rit bij te houden en familieleden op de kaart te zien.';

  @override
  String get dawarichNietIngelogd => 'Niet ingelogd';

  @override
  String get dawarichServer => 'Server';

  @override
  String get dawarichMetWachtwoord => 'E-mail en wachtwoord';

  @override
  String get dawarichMetSleutel => 'API-sleutel';

  @override
  String get dawarichEmail => 'E-mail';

  @override
  String get dawarichWachtwoord => 'Wachtwoord';

  @override
  String get dawarichSleutel => 'API-sleutel';

  @override
  String get dawarichSleutelUitleg =>
      'Te vinden in Dawarich onder Instellingen. Gebruik dit als je server alleen OIDC kent.';

  @override
  String get dawarichInloggen => 'Inloggen';

  @override
  String get dawarichUitloggen => 'Uitloggen';

  @override
  String get dawarichCode => 'Code voor tweestapsverificatie';

  @override
  String get dawarichCodeUitleg =>
      'De code uit je authenticator-app, of een back-upcode.';

  @override
  String get dawarichBevestig => 'Bevestigen';

  @override
  String get annuleren => 'Annuleren';

  @override
  String get dawarichWeb =>
      'In de browser moet Dawarich CORS toestaan voor dit adres.';

  @override
  String get dawarichFoutInlog => 'Onjuiste gegevens.';

  @override
  String get dawarichFoutWachtwoordUit =>
      'Deze server staat inloggen met een wachtwoord niet toe. Gebruik een API-sleutel.';

  @override
  String get dawarichFoutGeblokkeerd =>
      'Te vaak een verkeerde code. Probeer het later opnieuw.';

  @override
  String dawarichFoutVerbinding(String detail) {
    return 'Dawarich is niet te bereiken ($detail).';
  }

  @override
  String dawarichFoutOnbekend(String detail) {
    return 'Er ging iets mis ($detail).';
  }

  @override
  String dawarichIngelogdAls(String email) {
    return 'Ingelogd als $email';
  }

  @override
  String get dawarichFamilie => 'Familie';

  @override
  String get dawarichFamilieDelen => 'Locatie delen met familie';

  @override
  String dawarichDeeltTot(String tijd) {
    return 'Tot $tijd';
  }

  @override
  String get dawarichDeeltAltijd => 'Tot je het uitzet';

  @override
  String get dawarichDeeltNiet => 'Je familie ziet je locatie niet';

  @override
  String get dawarichGeenFamilie =>
      'Je zit nog niet in een familie. Maak er een of word lid op de Dawarich-website.';

  @override
  String get dawarichNaarWebsite => 'Naar de website';

  @override
  String get dawarichGeenAbonnement =>
      'Familie zit niet in je Dawarich-abonnement.';

  @override
  String get dawarichHoeLang => 'Hoe lang delen?';

  @override
  String dawarichDuur(String duur) {
    String _temp0 = intl.Intl.selectLogic(duur, {
      'uur1': '1 uur',
      'uur6': '6 uur',
      'uur12': '12 uur',
      'uur24': '24 uur',
      'other': 'Tot ik het uitzet',
    });
    return '$_temp0';
  }

  @override
  String get dawarichDelenOnderweg => 'Locatie delen tijdens navigeren';

  @override
  String get dawarichDelenOnderwegUitleg =>
      'Stuurt je rit naar Dawarich. Interval en afstand stel je in bij Locatie delen.';

  @override
  String get dawarichToonFamilie => 'Familieleden op de kaart';

  @override
  String get dawarichToonFamilieUitleg =>
      'Elke 30 seconden bijgewerkt, zolang de app open is.';

  @override
  String get dawarichFamilieDeelt => 'familie deelt';

  @override
  String get deelViaDawarich => 'Ingesteld via je Dawarich-account.';

  @override
  String familieGeleden(int minuten) {
    String _temp0 = intl.Intl.pluralLogic(
      minuten,
      locale: localeName,
      other: '$minuten minuten geleden',
      one: '1 minuut geleden',
      zero: 'zojuist',
    );
    return '$_temp0';
  }

  @override
  String familieBatterij(int procent) {
    return 'batterij $procent%';
  }

  @override
  String familieUrenGeleden(int uren) {
    String _temp0 = intl.Intl.pluralLogic(
      uren,
      locale: localeName,
      other: '$uren uur geleden',
      one: '1 uur geleden',
    );
    return '$_temp0';
  }

  @override
  String familieDagenGeleden(int dagen) {
    String _temp0 = intl.Intl.pluralLogic(
      dagen,
      locale: localeName,
      other: '$dagen dagen geleden',
      one: '1 dag geleden',
    );
    return '$_temp0';
  }

  @override
  String get familieVolgen => 'Volgen';

  @override
  String get familieVolgt => 'Wordt gevolgd';

  @override
  String get instellingenGroepKaart => 'Kaart en route';

  @override
  String get instellingenGroepDelen => 'Delen';

  @override
  String get instellingenGroepApp => 'App';

  @override
  String get instellingenKaart => 'Kaart';

  @override
  String get dagEnNacht => 'Dag en nacht';

  @override
  String get themaAlleenKaart =>
      'Alleen bij de stijl Kaart; Licht en Donker zijn al een keuze.';

  @override
  String get lagen => 'Lagen';

  @override
  String get verkeerOpKaartUitleg =>
      'Afsluitingen, werk op de weg en files op de kaart';

  @override
  String get vervoer => 'Vervoer';

  @override
  String get vervoerUitleg => 'Waarmee een nieuwe route berekend wordt.';

  @override
  String get opgeslagen => 'Opgeslagen';

  @override
  String get overSamenvatting => 'Versie, bronnen en licenties';

  @override
  String get dawarichAccount => 'Account';

  @override
  String get dawarichNavigeren => 'Navigeren';

  @override
  String get deelVerbinding => 'Verbinding';

  @override
  String get deelPunten => 'Punten';
}
