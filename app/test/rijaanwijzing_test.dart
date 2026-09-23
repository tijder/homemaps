import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/models/route.dart';
import 'package:homemaps/navigatie/navigatie_provider.dart';
import 'package:homemaps/navigatie/rijstrook_keuze.dart';
import 'package:homemaps/navigatie/volger.dart';
import 'package:homemaps/services/valhalla_service.dart';
import 'package:homemaps/widgets/manoeuvre_pictogram.dart';
import 'package:homemaps/widgets/navigatie_balk.dart';

import 'navigatie_test.dart' show stroe;

/// De Meern -> Utrecht Science Park over de A12, A27 en A28 (knooppunten
/// Lunetten en Rijnsweerd), zoals Valhalla 3.9 hem gaf.
RouteOptie utrecht() {
  final json = jsonDecode(
    File('test/fixtures/valhalla_utrecht.json').readAsStringSync(),
  );
  return RouteOptie.vanValhalla(
    (json['trip'] as Map).cast<String, dynamic>(),
    hoogteInterval: 30,
  );
}

/// Dezelfde route als `trace_route` met `format: osrm`, alleen de kruisingen
/// met rijstroken.
List<RijstrookAdvies> utrechtRijstroken() => ValhallaService.leesRijstroken(
  (jsonDecode(
    File('test/fixtures/valhalla_utrecht_rijstroken.json').readAsStringSync(),
  ) as Map).cast<String, dynamic>(),
);

void main() {
  test('rotonde: de afslag en de hoek van de uitrit, op en af hetzelfde', () {
    final rotondes = [
      for (final m in stroe().manoeuvres)
        if (m.isRotonde) m,
    ];
    expect([for (final m in rotondes) m.type], [26, 27, 26, 27]);
    expect([for (final m in rotondes) m.rotondeAfslag], [2, 2, 2, 2]);
    // Eerste: 288° erop, 323° eraf -- schuin rechts. Tweede: 267° erop, 261°
    // eraf -- vrijwel rechtdoor.
    expect(rotondes[0].rotondeHoek, closeTo(35, 0.1));
    expect(rotondes[1].rotondeHoek, rotondes[0].rotondeHoek);
    expect(rotondes[2].rotondeHoek, closeTo(354, 0.1));
    expect(rotondes[3].rotondeHoek, rotondes[2].rotondeHoek);
  });

  test('bord: afritnummer, wegnummers, richtingen en knooppunt', () {
    final m = utrecht().manoeuvres;
    final afrit = m.firstWhere((m) => m.type == 20).bord!;
    expect(afrit.afrit, '15');
    expect(afrit.wegen, ['A12']);
    expect(afrit.richtingen, ['Utrecht']);

    final lunetten = m.firstWhere(
      (m) => m.bord?.wegen.contains('A27') ?? false,
    );
    expect(lunetten.bord!.naam, 'Knooppunt Lunetten');
    expect(lunetten.bord!.richtingen.first, 'Amersfoort');

    // Een rotonde-afrit met een lege `sign` heeft geen bord.
    expect(Bord.vanValhalla(const {}), isNull);
    expect(stroe().manoeuvres.where((m) => m.bord != null), isEmpty);
  });

  test('rijstroken uit het OSRM-antwoord, op volgorde langs de route', () {
    final advies = utrechtRijstroken();
    expect(advies, isNotEmpty);
    // Vlak na de oprit op de A12: drie stroken rechtdoor (goed), drie schuin
    // rechts eraf (niet).
    final a12 = advies.firstWhere((a) => a.stroken.length == 6);
    expect(
      [for (final s in a12.stroken) s.goed],
      [true, true, true, false, false, false],
    );
    expect(a12.stroken.first.richtingen, ['straight']);
    expect(a12.stroken.first.gebruik, 'straight');

    final langs = RouteVolger(utrecht())
        .langsVan([for (final a in advies) a.plek]);
    expect(langs, everyElement(isNotNull));
    for (var i = 1; i < langs.length; i++) {
      expect(langs[i]!, greaterThanOrEqualTo(langs[i - 1]!));
    }
  });

  Widget app(Widget kind) => MaterialApp(
    locale: const Locale('nl'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: kind),
  );

  testWidgets(
    'een rotonde tekent zijn uitrit, de rest is een gewoon pictogram',
    (tester) async {
      final m = stroe().manoeuvres;
      await tester.pumpWidget(
        app(
          Row(
            children: [
              ManoeuvreIcoon(m.firstWhere((m) => m.type == 26)),
              ManoeuvreIcoon(m.firstWhere((m) => m.type == 15)),
            ],
          ),
        ),
      );
      final schilder = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<RotondeSchilder>()
          .single;
      expect(schilder.hoek, closeTo(35, 0.1));
      expect(schilder.afslag, 2);
      expect(find.byIcon(Icons.turn_left), findsOneWidget);
      expect(find.byIcon(Icons.roundabout_right), findsNothing);
    },
  );

  testWidgets('splitsing en afrit: de tak die je neemt, niet twee keuzes', (
    tester,
  ) async {
    final m = utrecht().manoeuvres;
    await tester.pumpWidget(
      app(
        Row(
          children: [
            ManoeuvreIcoon(m.firstWhere((m) => m.type == 23)),
            ManoeuvreIcoon(m.firstWhere((m) => m.type == 24)),
            ManoeuvreIcoon(m.firstWhere((m) => m.type == 20)),
          ],
        ),
      ),
    );
    final kanten = [
      for (final c in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
        if (c.painter case final SplitsingSchilder s) s.rechts,
    ];
    expect(kanten, [true, false, true]);
    expect(find.byIcon(Icons.fork_right), findsNothing);
  });

  testWidgets('na "rotonde op" niet nog eens "rotonde af" als daarna', (
    tester,
  ) async {
    final route = stroe();
    final op = route.manoeuvres.indexWhere((m) => m.type == 26);
    await tester.pumpWidget(
      app(
        NavigatieKop(
          NavigatieToestand(
            route: route,
            doelen: const [],
            stand: NavStand(
              opRoute: route.punten.first,
              segment: 0,
              langs: 0,
              afwijking: 0,
              routeKoers: 0,
              volgende: op,
              totVolgende: 100,
              restMeters: 5000,
              restSeconden: 600,
              vanRoute: false,
              aangekomen: false,
            ),
          ),
        ),
      ),
    );
    // Na de eerste rotonde is het nog een eind: geen "Daarna" meer.
    expect(find.text('Daarna'), findsNothing);
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where((c) => c.painter is RotondeSchilder),
      hasLength(1),
    );
  });

  testWidgets('kop bij een afrit: bord en rijstroken', (tester) async {
    final route = utrecht();
    final afrit = route.manoeuvres.indexWhere((m) => m.type == 20);
    final stand = NavStand(
      opRoute: route.punten.first,
      segment: 0,
      langs: 0,
      afwijking: 0,
      routeKoers: 0,
      volgende: afrit,
      totVolgende: 400,
      restMeters: 10000,
      restSeconden: 600,
      vanRoute: false,
      aangekomen: false,
    );
    await tester.pumpWidget(
      app(
        NavigatieKop(
          NavigatieToestand(
            route: route,
            doelen: const [],
            stand: stand,
            rijstroken: (
              over: 350,
              bijManoeuvre: true,
              stroken: const [
                Rijstrook(richtingen: ['straight'], goed: false),
                Rijstrook(
                  richtingen: ['straight', 'right'],
                  goed: true,
                  gebruik: 'right',
                ),
                Rijstrook(richtingen: ['right'], goed: true),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(WegBord), findsOneWidget);
    expect(find.text('Afrit 15'), findsOneWidget);
    expect(find.text('A12'), findsOneWidget);
    expect(find.text('Utrecht'), findsOneWidget);
    expect(find.byType(RijstrookBalk), findsOneWidget);
    // Van de gecombineerde strook alleen de richting die je neemt.
    expect(
      find.descendant(
        of: find.byType(RijstrookBalk),
        matching: find.byIcon(Icons.turn_right),
      ),
      findsNWidgets(2),
    );
    expect(find.bySemanticsLabel('2 goede rijstroken van 3'), findsOneWidget);
  });

  group('welke rijstroken in de kop', () {
    const splitsing = [
      Rijstrook(richtingen: ['straight'], goed: true),
      Rijstrook(richtingen: ['straight'], goed: true),
      Rijstrook(richtingen: ['right'], goed: false),
    ];
    const afrit = [
      Rijstrook(richtingen: ['straight'], goed: false),
      Rijstrook(richtingen: ['right'], goed: true),
    ];
    // Een afrit waar je niet af moet op 1200 m, de jouwe op 1800 m.
    const kruisingen = [
      (langs: 1200.0, stroken: splitsing),
      (langs: 1800.0, stroken: afrit),
    ];
    RijstrookKeuze? bij(double langs, {double? kmu = 100}) => kiesRijstroken(
      kruisingen,
      langs: langs,
      manoeuvre: 1800,
      snelheid: kmu == null ? null : kmu / 3.6,
    );

    test('ver voor de afrit nog niets, ook niet de afrit ervoor', () {
      expect(bij(0), isNull);
      expect(bij(700), isNull);
    });

    test('vlak voor een afrit ervoor: die, met zijn eigen afstand', () {
      final keuze = bij(900)!;
      expect(keuze.stroken, same(splitsing));
      expect(keuze.bijManoeuvre, isFalse);
      expect(keuze.over, 300);
    });

    test('daarna de stroken van de afrit zelf', () {
      final keuze = bij(1250)!;
      expect(keuze.stroken, same(afrit));
      expect(keuze.bijManoeuvre, isTrue);
      expect(keuze.over, 550);
    });

    test('hoe langzamer, hoe later', () {
      // 50 km/u: ongeveer 500 m van tevoren.
      expect(bij(1250, kmu: 50), isNull);
      expect(bij(1350, kmu: 50)!.stroken, same(afrit));
      // Stapvoets toch minstens 300 m.
      expect(bij(1500, kmu: 5)!.stroken, same(afrit));
      // Geen snelheid: het maximum.
      expect(bij(1250, kmu: null)!.stroken, same(afrit));
    });

    test('elke strook goed: niets te kiezen', () {
      expect(
        kiesRijstroken(
          [
            (
              langs: 500.0,
              stroken: splitsing
                  .map((s) => Rijstrook(richtingen: s.richtingen, goed: true))
                  .toList(),
            ),
          ],
          langs: 400,
          manoeuvre: 500,
        ),
        isNull,
      );
    });
  });

  testWidgets('rijstroken van een kruising ervoor: met afstand', (
    tester,
  ) async {
    const stroken = [
      Rijstrook(richtingen: ['straight'], goed: true),
      Rijstrook(richtingen: ['right'], goed: false),
    ];
    await tester.pumpWidget(app(const RijstrookBalk(stroken, over: 312)));
    expect(find.text('300 m'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Over 300 m: 1 goede rijstrook van 2'),
      findsOneWidget,
    );

    await tester.pumpWidget(app(const RijstrookBalk(stroken)));
    expect(find.text('300 m'), findsNothing);
    expect(find.bySemanticsLabel('1 goede rijstrook van 2'), findsOneWidget);
  });
}
