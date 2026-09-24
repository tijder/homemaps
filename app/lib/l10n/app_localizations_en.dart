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
  String get themaAutomatisch => 'Automatic';

  @override
  String get themaDag => 'Always day';

  @override
  String get themaNacht => 'Always night';

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
  String korteActie(String soort) {
    String _temp0 = intl.Intl.selectLogic(soort, {
      'oprit': 'Take the ramp',
      'afrit': 'Take the exit',
      'rechtdoor': 'Keep straight',
      'rechts': 'Keep right',
      'links': 'Keep left',
      'invoegen': 'Merge',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String afrit(String nummer) {
    return 'Exit $nummer';
  }

  @override
  String rijstrokenOver(String afstand, String stroken) {
    return 'In $afstand: $stroken';
  }

  @override
  String rijstrokenGoed(int goed, int totaal) {
    String _temp0 = intl.Intl.pluralLogic(
      goed,
      locale: localeName,
      other: '$goed correct lanes',
      one: '1 correct lane',
    );
    return '$_temp0 of $totaal';
  }

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
  String maximumsnelheidTijdelijk(int kmu) {
    return 'Temporary speed limit $kmu km/h';
  }

  @override
  String maximumsnelheidMatrix(int kmu) {
    return 'Speed limit $kmu km/h on the overhead signs';
  }

  @override
  String get meldingOngeval => 'Accident';

  @override
  String get meldingPech => 'Broken-down vehicle';

  @override
  String get meldingObstakel => 'Object on the road';

  @override
  String get meldingBrug => 'Open bridge';

  @override
  String get matrixborden => 'Overhead lane signs';

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

  @override
  String get locatieDelen => 'Location sharing';

  @override
  String get locatieDelenUitleg =>
      'Send your position to your own server, like Colota does. Only while navigating.';

  @override
  String get locatieDelenAan => 'Share while navigating';

  @override
  String get deelUit => 'Off';

  @override
  String get deelServer => 'Server';

  @override
  String get deelAangepast => 'Custom server';

  @override
  String deelSjabloonUitleg(String sjabloon) {
    String _temp0 = intl.Intl.selectLogic(sjabloon, {
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
  String get deelUrl => 'Address (URL)';

  @override
  String get deelUrlOngeldig =>
      'Enter an address starting with http:// or https://.';

  @override
  String get deelUrlWeb => 'In the browser the server must allow CORS.';

  @override
  String get deelMethode => 'Method';

  @override
  String get deelInlog => 'Authentication';

  @override
  String get deelInlogGeen => 'None';

  @override
  String get deelGebruiker => 'Username';

  @override
  String get deelWachtwoord => 'Password';

  @override
  String get deelToken => 'Token';

  @override
  String get deelVeldnamen => 'Field names';

  @override
  String get deelVeldnamenUitleg =>
      'One per line as field=name, e.g. lat=latitude. Fields: lat, lon, acc, alt, vel, tst, bear.';

  @override
  String get deelExtraVelden => 'Fixed fields';

  @override
  String get deelExtraVeldenUitleg =>
      'One per line as name=value; sent with every point.';

  @override
  String get deelInterval => 'Every … seconds';

  @override
  String get deelMinAfstand => 'Or after … metres';

  @override
  String get deelTesten => 'Test connection';

  @override
  String get deelTestGelukt => 'The server received the point.';

  @override
  String deelTestMislukt(String fout) {
    return 'Failed: $fout';
  }

  @override
  String get deelStatus => 'Status';

  @override
  String deelLaatst(String tijd) {
    return 'Last sent at $tijd';
  }

  @override
  String get deelNogNiets => 'Nothing sent yet';

  @override
  String deelInWachtrij(int aantal) {
    String _temp0 = intl.Intl.pluralLogic(
      aantal,
      locale: localeName,
      other: '$aantal points queued',
      one: '1 point queued',
      zero: 'Queue empty',
    );
    return '$_temp0';
  }

  @override
  String deelFout(String fout) {
    return 'Error: $fout';
  }

  @override
  String get deelGestopt => 'Stopped until you change the settings.';

  @override
  String get deelWisWachtrij => 'Clear queue';

  @override
  String get deelVoorbeeld => 'Example';

  @override
  String get navigatieMeldingDelen =>
      'HomeMaps follows your location for the route and shares it with your server.';

  @override
  String get overHomeMaps => 'About HomeMaps';

  @override
  String versie(String versie) {
    return 'Version $versie';
  }

  @override
  String get overBeschrijving =>
      'Navigation on your own server: map, routes, search and traffic.';

  @override
  String get bronnen => 'Data and software';

  @override
  String get bronKaartgegevens => 'Map data © OpenStreetMap contributors';

  @override
  String get bronTegels => 'Map tiles and style';

  @override
  String get bronRoutes => 'Routing and navigation';

  @override
  String get bronZoeken => 'Search';

  @override
  String get bronVerkeer => 'Traffic, roadworks and lane signals';

  @override
  String get broncode => 'Source code';

  @override
  String get licenties => 'Licenses';

  @override
  String get dawarich => 'Dawarich';

  @override
  String get dawarichUitleg =>
      'Sign in to your own Dawarich server to share your location with your family, record your trips while navigating and see family members on the map.';

  @override
  String get dawarichNietIngelogd => 'Not signed in';

  @override
  String get dawarichServer => 'Server';

  @override
  String get dawarichMetWachtwoord => 'Email and password';

  @override
  String get dawarichMetSleutel => 'API key';

  @override
  String get dawarichEmail => 'Email';

  @override
  String get dawarichWachtwoord => 'Password';

  @override
  String get dawarichSleutel => 'API key';

  @override
  String get dawarichSleutelUitleg =>
      'Found in Dawarich under Settings. Use this if your server only supports OIDC.';

  @override
  String get dawarichInloggen => 'Sign in';

  @override
  String get dawarichUitloggen => 'Sign out';

  @override
  String get dawarichCode => 'Two-factor code';

  @override
  String get dawarichCodeUitleg =>
      'The code from your authenticator app, or a backup code.';

  @override
  String get dawarichBevestig => 'Confirm';

  @override
  String get annuleren => 'Cancel';

  @override
  String get dawarichWeb =>
      'In the browser, Dawarich must allow CORS for this address.';

  @override
  String get dawarichFoutInlog => 'Incorrect credentials.';

  @override
  String get dawarichFoutWachtwoordUit =>
      'This server does not allow signing in with a password. Use an API key.';

  @override
  String get dawarichFoutGeblokkeerd =>
      'Too many wrong codes. Try again later.';

  @override
  String dawarichFoutVerbinding(String detail) {
    return 'Cannot reach Dawarich ($detail).';
  }

  @override
  String dawarichFoutOnbekend(String detail) {
    return 'Something went wrong ($detail).';
  }

  @override
  String dawarichIngelogdAls(String email) {
    return 'Signed in as $email';
  }

  @override
  String get dawarichFamilie => 'Family';

  @override
  String get dawarichFamilieDelen => 'Share location with family';

  @override
  String dawarichDeeltTot(String tijd) {
    return 'Until $tijd';
  }

  @override
  String get dawarichDeeltAltijd => 'Until you turn it off';

  @override
  String get dawarichDeeltNiet => 'Your family can\'t see your location';

  @override
  String get dawarichGeenFamilie =>
      'You\'re not in a family yet. Create or join one on the Dawarich website.';

  @override
  String get dawarichNaarWebsite => 'Open website';

  @override
  String get dawarichGeenAbonnement =>
      'Family is not included in your Dawarich plan.';

  @override
  String get dawarichHoeLang => 'Share for how long?';

  @override
  String dawarichDuur(String duur) {
    String _temp0 = intl.Intl.selectLogic(duur, {
      'uur1': '1 hour',
      'uur6': '6 hours',
      'uur12': '12 hours',
      'uur24': '24 hours',
      'other': 'Until I turn it off',
    });
    return '$_temp0';
  }

  @override
  String get dawarichDelenOnderweg => 'Share location while navigating';

  @override
  String get dawarichDelenOnderwegUitleg =>
      'Sends your trip to Dawarich. Set interval and distance under Location sharing.';

  @override
  String get dawarichToonFamilie => 'Family members on the map';

  @override
  String get dawarichToonFamilieUitleg =>
      'Updated every 30 seconds while the app is open.';

  @override
  String get dawarichFamilieDeelt => 'family sharing';

  @override
  String get deelViaDawarich => 'Set up through your Dawarich account.';

  @override
  String familieGeleden(int minuten) {
    String _temp0 = intl.Intl.pluralLogic(
      minuten,
      locale: localeName,
      other: '$minuten minutes ago',
      one: '1 minute ago',
      zero: 'just now',
    );
    return '$_temp0';
  }

  @override
  String familieBatterij(int procent) {
    return 'battery $procent%';
  }

  @override
  String familieUrenGeleden(int uren) {
    String _temp0 = intl.Intl.pluralLogic(
      uren,
      locale: localeName,
      other: '$uren hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String familieDagenGeleden(int dagen) {
    String _temp0 = intl.Intl.pluralLogic(
      dagen,
      locale: localeName,
      other: '$dagen days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get familieVolgen => 'Follow';

  @override
  String get familieVolgt => 'Following';

  @override
  String get instellingenGroepKaart => 'Map and route';

  @override
  String get instellingenGroepDelen => 'Sharing';

  @override
  String get instellingenGroepApp => 'App';

  @override
  String get instellingenKaart => 'Map';

  @override
  String get dagEnNacht => 'Day and night';

  @override
  String get themaAlleenKaart =>
      'Only for the Map style; Light and Dark are already a choice.';

  @override
  String get lagen => 'Layers';

  @override
  String get verkeerOpKaartUitleg =>
      'Closures, road works and traffic jams on the map';

  @override
  String get vervoer => 'Transport';

  @override
  String get vervoerUitleg => 'Used to calculate a new route.';

  @override
  String get opgeslagen => 'Saved';

  @override
  String get overSamenvatting => 'Version, sources and licenses';

  @override
  String get dawarichAccount => 'Account';

  @override
  String get dawarichNavigeren => 'Navigation';

  @override
  String get deelVerbinding => 'Connection';

  @override
  String get deelPunten => 'Points';
}
