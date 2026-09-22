import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/models/profiel.dart';
import 'package:homemaps/models/route.dart';
import 'package:homemaps/navigatie/aankondiger.dart';
import 'package:homemaps/navigatie/volger.dart';
import 'package:homemaps/providers/locatie.dart';
import 'package:homemaps/utils/afstand.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Stroe (Heetkamperweg) -> Voorthuizen, zoals Valhalla hem gaf.
RouteOptie stroe() {
  final json = jsonDecode(
    File('test/fixtures/valhalla_stroe.json').readAsStringSync(),
  );
  return RouteOptie.vanValhalla(
    (json['trip'] as Map).cast<String, dynamic>(),
    hoogteInterval: 30,
  );
}

/// Punten om de [stap] meter langs de lijn, het eindpunt erbij.
List<LatLng> langs(List<LatLng> lijn, double stap) {
  final uit = [lijn.first];
  var over = stap;
  for (var i = 1; i < lijn.length; i++) {
    var a = lijn[i - 1];
    final b = lijn[i];
    var stuk = meters(a, b);
    while (stuk >= over) {
      final t = over / stuk;
      a = LatLng(
        a.latitude + t * (b.latitude - a.latitude),
        a.longitude + t * (b.longitude - a.longitude),
      );
      uit.add(a);
      stuk -= over;
      over = stap;
    }
    over -= stuk;
  }
  return uit..add(lijn.last);
}

LocatieFix fix(
  LatLng punt, {
  double snelheid = 13,
  double nauwkeurigheid = 5,
}) => LocatieFix(
  punt: punt,
  tijd: DateTime(2026),
  nauwkeurigheid: nauwkeurigheid,
  snelheid: snelheid,
);

/// [meter] naar het oosten verschoven (bij 52° is een lengtegraad ~68 km).
LatLng oost(LatLng p, double meter) => LatLng(
  p.latitude,
  p.longitude + meter / (111320 * cos(p.latitude * pi / 180)),
);

void main() {
  final route = stroe();

  test('de manoeuvres krijgen de gesproken zinnen en straten', () {
    final links = route.manoeuvres[1];
    expect(links.stemVooraf, 'Links afslaan naar Houtbeekweg.');
    expect(links.stemVlakVoor, 'Links afslaan naar Houtbeekweg.');
    expect(links.stemNa, '700 meter doorgaan.');
    expect(links.straten, ['Houtbeekweg']);
    expect(links.eindVormIndex, greaterThan(links.vormIndex));
    expect(route.manoeuvres.last.isBestemming, isTrue);
  });

  test(
    'langs de route: vooruit, nooit van de route, aangekomen aan het eind',
    () {
      final volger = RouteVolger(route);
      final begin = volger.werkBij(fix(route.punten.first));
      // Zonder file is de rest bij vertrek de hele reistijd.
      expect(
        begin.restSeconden,
        closeTo(route.seconden, route.seconden * 0.02),
      );
      expect(begin.restMeters, closeTo(route.meters, route.meters * 0.02));
      var vorige = begin;
      for (final punt in langs(route.punten, 25).skip(1)) {
        final stand = volger.werkBij(fix(punt));
        expect(stand.vanRoute, isFalse);
        expect(stand.langs, greaterThanOrEqualTo(vorige.langs - 1));
        expect(stand.volgende, greaterThanOrEqualTo(vorige.volgende));
        vorige = stand;
      }
      expect(vorige.aangekomen, isTrue);
      expect(vorige.volgende, route.manoeuvres.length - 1);
    },
  );

  test('ruis naast de weg is geen afwijking, drie keer ver weg wel', () {
    final volger = RouteVolger(route);
    final punten = langs(route.punten, 25);
    for (final punt in punten.take(40)) {
      volger.werkBij(fix(punt));
    }
    // 25 m ernaast bij een onzekerheid van 10 m: gewoon op de route.
    expect(
      volger.werkBij(fix(oost(punten[40], 25), nauwkeurigheid: 10)).vanRoute,
      isFalse,
    );
    final ver = [for (var i = 41; i < 44; i++) oost(punten[i], 150)];
    expect(volger.werkBij(fix(ver[0])).vanRoute, isFalse);
    expect(volger.werkBij(fix(ver[1])).vanRoute, isFalse);
    expect(volger.werkBij(fix(ver[2])).vanRoute, isTrue);
    // Terug op de weg: weer goed.
    expect(volger.werkBij(fix(punten[45])).vanRoute, isFalse);
  });

  List<String> rijd(Profiel profiel, double snelheid) {
    final volger = RouteVolger(route);
    final aankondiger = Aankondiger(
      route,
      profiel,
      metAfstand: (m, zin) => 'Over ${m.round()} m: $zin',
    );
    return [
      for (final punt in langs(route.punten, 10))
        ...aankondiger.bij(
          volger.werkBij(fix(punt, snelheid: snelheid)),
          snelheid,
        ),
    ];
  }

  test('elke zin één keer, in de volgorde van de route', () {
    final zinnen = rijd(Profiel.auto, 14);
    expect(zinnen.first, route.manoeuvres.first.stemVlakVoor);
    expect(zinnen.last, 'Aangekomen op je bestemming.');
    // Elke bocht krijgt zijn "vlak voor"-zin.
    for (final m in route.manoeuvres.skip(1)) {
      expect(zinnen, contains(m.stemVlakVoor), reason: m.instructie);
    }
    // Geen zin twee keer achter elkaar (dezelfde tekst mag wel bij twee
    // verschillende bochten voorkomen).
    for (var i = 1; i < zinnen.length; i++) {
      expect(zinnen[i], isNot(zinnen[i - 1]));
    }
  });

  test('na een kort stuk geen "vooraf": te laat, alleen "vlak voor"', () {
    // Wolweg is 40 m; de bocht naar Tolnegenweg daarna heeft geen tijd voor een
    // aankondiging ruim van tevoren.
    final zinnen = rijd(Profiel.auto, 14);
    final tolnegenweg = route.manoeuvres[3];
    expect(tolnegenweg.straten, ['Tolnegenweg']);
    expect(zinnen.where((z) => z == tolnegenweg.stemVlakVoor), hasLength(1));
    expect(
      zinnen.where((z) => z.startsWith('Over ') && z.contains('Tolnegenweg')),
      isEmpty,
    );
  });

  test('wat het vertrek al noemde, komt niet nog eens vooraf', () {
    // "Daarna, over 400 meter, Links afslaan naar Houtbeekweg."
    expect(route.manoeuvres.first.metVolgende, isTrue);
    final zinnen = rijd(Profiel.auto, 14);
    expect(
      zinnen.where((z) => z.startsWith('Over ')).first,
      isNot(contains('Houtbeekweg')),
    );
  });

  test('vooraf met de afstand erbij', () {
    final zinnen = rijd(Profiel.auto, 14);
    final vooraf = zinnen.where((z) => z.startsWith('Over ')).toList();
    expect(vooraf, isNotEmpty);
    for (final zin in vooraf) {
      final m = int.parse(RegExp(r'Over (\d+) m').firstMatch(zin)!.group(1)!);
      // In het venster: tussen 60% en 100% van 35 s bij 14 m/s (490 m).
      expect(m, inInclusiveRange(290, 490));
    }
  });

  test('fiets kondigt later aan dan auto', () {
    String zo(double m, String zin) => zin;
    final auto = Aankondiger(route, Profiel.auto, metAfstand: zo);
    final fiets = Aankondiger(route, Profiel.fiets, metAfstand: zo);
    expect(fiets.voorafAfstand(5), lessThan(auto.voorafAfstand(5)));
    expect(auto.voorafAfstand(33), 1155);
    expect(auto.vlakVoorAfstand(0), 60);
  });
}
