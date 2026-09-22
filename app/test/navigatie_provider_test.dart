import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/models/plaats.dart';
import 'package:homemaps/models/profiel.dart';
import 'package:homemaps/models/route.dart';
import 'package:homemaps/navigatie/navigatie_provider.dart';
import 'package:homemaps/navigatie/stem.dart';
import 'package:homemaps/providers/diensten.dart';
import 'package:homemaps/providers/locatie.dart';
import 'package:homemaps/services/valhalla_service.dart';
import 'package:homemaps/utils/afstand.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'hulp/nep_bron.dart' hide fix;
import 'navigatie_test.dart' show fix, langs, oost, stroe;

class NepStem implements Stem {
  final zinnen = <String>[];

  @override
  Future<void> begin(String taal) async {}

  @override
  void zeg(String zin) => zinnen.add(zin);

  @override
  Future<void> stop() async {}
}

/// Geeft altijd dezelfde route terug en onthoudt de verzoeken.
class NepValhalla extends ValhallaService {
  NepValhalla(this.antwoord) : super(Dio(), 'http://nep');

  RouteOptie antwoord;

  /// Reistijd over een lijn; standaard onbekend.
  double? Function(List<LatLng> lijn) tijd = (_) => null;

  List<int?>? limieten;

  @override
  Future<List<int?>?> snelheidsLimieten(
    List<LatLng> lijn,
    Profiel profiel, {
    CancelToken? annuleer,
  }) async => limieten;

  @override
  Future<double?> reistijd(
    List<LatLng> lijn,
    Profiel profiel, {
    bool live = false,
    DateTime? nu,
    CancelToken? annuleer,
  }) async => tijd(lijn);

  /// Wordt bij elk verzoek aangeroepen, om vast te leggen hoe het er toen voor
  /// stond.
  void Function()? bijVerzoek;
  final verzoeken =
      <({List<LatLng> punten, double? koers, bool alternatieven})>[];

  @override
  Future<List<RouteOptie>> route(
    List<LatLng> punten,
    Profiel profiel, {
    required String taal,
    bool liveVerkeer = true,
    bool vermijdSnelwegen = false,
    bool vermijdTol = false,
    bool vermijdVeren = false,
    bool alternatieven = true,
    double? koers,
    CancelToken? annuleer,
  }) async {
    bijVerzoek?.call();
    verzoeken.add((punten: punten, koers: koers, alternatieven: alternatieven));
    return [antwoord];
  }
}

final teksten = NavTeksten(
  taal: 'nl-NL',
  meldingTitel: 'Navigatie naar Voorthuizen',
  meldingTekst: 'x',
  herberekenen: 'Route wordt herberekend.',
  snellereRoute: (m) => 'Snellere route, $m minuten',
  metAfstand: (m, zin) => 'Over ${m.round()} m $zin',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final route = stroe();
  final doel = Plaats(naam: 'Voorthuizen', punt: route.punten.last);

  late NepBron bron;
  late NepStem stem;
  late NepValhalla valhalla;
  late ProviderContainer c;

  setUp(() async {
    bron = NepBron(Toestemming.ja);
    stem = NepStem();
    valhalla = NepValhalla(route);
    c = ProviderContainer(
      overrides: [
        locatieBronProvider.overrideWithValue(bron),
        stemProvider.overrideWithValue(stem),
        valhallaProvider.overrideWithValue(valhalla),
      ],
    );
    addTearDown(c.dispose);
    final wacht = c.read(locatieProvider.notifier).zetAan();
    await Future<void>.delayed(Duration.zero);
    bron.fixes.add(fix(route.punten.first));
    await wacht;
  });

  Future<void> rijNaar(LatLng punt) async {
    bron.fixes.add(fix(punt));
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> start() => c
      .read(navigatieProvider.notifier)
      .start(route: route, doelen: [doel], teksten: teksten);

  test(
    'start: melding op Android, eerste zin, en de stand loopt mee',
    () async {
      await start();
      expect(bron.laatsteMelding?.titel, 'Navigatie naar Voorthuizen');
      expect(bron.laatsteNauwkeurig, isTrue);
      expect(stem.zinnen.first, route.manoeuvres.first.stemVlakVoor);
      final punten = langs(route.punten, 20);
      for (final punt in punten.take(30)) {
        await rijNaar(punt);
      }
      final stand = c.read(navigatieProvider)!.stand!;
      expect(stand.langs, closeTo(29 * 20, 25));
      expect(stand.vanRoute, isFalse);
    },
  );

  test(
    'van de route af: herberekenen vanaf hier, met je rijrichting',
    () async {
      await start();
      final punten = langs(route.punten, 20);
      for (final punt in punten.take(30)) {
        await rijNaar(punt);
      }
      for (var i = 30; i < 34; i++) {
        bron.fixes.add(
          LocatieFix(
            punt: oost(punten[i], 200),
            tijd: DateTime(2026),
            nauwkeurigheid: 5,
            koers: 90,
            snelheid: 13,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
      expect(stem.zinnen, contains('Route wordt herberekend.'));
      expect(valhalla.verzoeken, hasLength(1));
      final verzoek = valhalla.verzoeken.single;
      expect(verzoek.koers, 90);
      expect(verzoek.alternatieven, isFalse);
      expect(verzoek.punten.last, doel.punt);
      // Binnen tien seconden niet nog eens, ook al ben je nog steeds ver weg.
      for (var i = 34; i < 38; i++) {
        await rijNaar(oost(punten[i], 200));
      }
      expect(valhalla.verzoeken, hasLength(1));
    },
  );

  test('ver van het begin gestart: meteen een route vanaf hier', () async {
    // Je staat 2 km naast het begin van de geplande route.
    await rijNaar(oost(route.punten.first, 2000));
    int? gezegdBijVerzoek;
    valhalla.bijVerzoek = () => gezegdBijVerzoek ??= stem.zinnen.length;
    await start();
    expect(valhalla.verzoeken, hasLength(1));
    expect(
      valhalla.verzoeken.single.punten.first.longitude,
      greaterThan(route.punten.first.longitude),
    );
    // Niet eerst de instructies van de geplande route voorlezen.
    expect(gezegdBijVerzoek, 0);
  });

  test('aankomst: "Aangekomen", daarna geen achtergronddienst meer', () async {
    await start();
    for (final punt in langs(route.punten, 50)) {
      await rijNaar(punt);
    }
    final nav = c.read(navigatieProvider)!;
    expect(nav.aangekomen, isTrue);
    expect(stem.zinnen.last, 'Aangekomen op je bestemming.');
    expect(bron.laatsteMelding, isNull);
    c.read(navigatieProvider.notifier).stop();
    expect(c.read(navigatieProvider), isNull);
  });

  group('snellere route onderweg', () {
    // Een "andere" route: dezelfde vorm, maar 500 m korter, zodat hij als een
    // andere weg telt.
    final anders = RouteOptie(
      meters: route.meters - 500,
      seconden: route.seconden,
      punten: route.punten,
      manoeuvres: route.manoeuvres,
      hoogtes: const [],
      hoogteInterval: 30,
      heeftTol: false,
      heeftVeer: false,
    );

    Future<void> onderweg() async {
      await start();
      for (final punt in langs(route.punten, 20).take(10)) {
        await rijNaar(punt);
      }
      valhalla.antwoord = anders;
    }

    /// De rest van de huidige route duurt [huidig] s, de nieuwe [nieuw] s.
    void tijden(double huidig, double nieuw) => valhalla.tijd = (lijn) =>
        // De nieuwe lijn begint bij het begin van de route; de rest van de
        // huidige waar je nu bent.
        meters(lijn.first, route.punten.first) < 1 ? nieuw : huidig;

    test('een voorstel, en pas wisselen na "Nemen"', () async {
      await onderweg();
      tijden(1200, 700);
      await c.read(navigatieProvider.notifier).zoekSneller();
      var nav = c.read(navigatieProvider)!;
      expect(nav.voorstel?.secondenSneller, 500);
      expect(nav.route, same(route), reason: 'nog niet gewisseld');
      expect(stem.zinnen.last, 'Snellere route, 8 minuten');

      c.read(navigatieProvider.notifier).neemVoorstel();
      nav = c.read(navigatieProvider)!;
      expect(nav.route, same(anders));
      expect(nav.voorstel, isNull);
    });

    test('"Negeren": de route blijft, en dezelfde komt niet terug', () async {
      await onderweg();
      tijden(1200, 700);
      await c.read(navigatieProvider.notifier).zoekSneller();
      c.read(navigatieProvider.notifier).negeerVoorstel();
      expect(c.read(navigatieProvider)!.voorstel, isNull);
      expect(c.read(navigatieProvider)!.route, same(route));
      await c.read(navigatieProvider.notifier).zoekSneller();
      expect(c.read(navigatieProvider)!.voorstel, isNull);
    });

    test('weinig winst: geen voorstel', () async {
      await onderweg();
      tijden(1200, 1100); // 100 s: onder de twee minuten
      await c.read(navigatieProvider.notifier).zoekSneller();
      expect(c.read(navigatieProvider)!.voorstel, isNull);
      tijden(3000, 2800); // 200 s, maar minder dan een tiende
      await c.read(navigatieProvider.notifier).zoekSneller();
      expect(c.read(navigatieProvider)!.voorstel, isNull);
    });
  });

  test('maximumsnelheid van het stuk waar je rijdt', () async {
    valhalla.limieten = [
      for (var i = 0; i < route.punten.length - 1; i++) i < 10 ? 60 : 80,
    ];
    await start();
    await Future<void>.delayed(Duration.zero);
    await rijNaar(route.punten[2]);
    expect(c.read(navigatieProvider)!.limiet, 60);
    for (final punt in langs(route.punten, 20).take(80)) {
      await rijNaar(punt);
    }
    final nav = c.read(navigatieProvider)!;
    expect(nav.stand!.segment, greaterThanOrEqualTo(10));
    expect(nav.limiet, 80);
  });
}
