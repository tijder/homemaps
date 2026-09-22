import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/l10n/app_localizations.dart';
import 'package:homemaps/navigatie/volger.dart';
import 'package:homemaps/utils/msi.dart';
import 'package:homemaps/widgets/navigatie_balk.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'navigatie_test.dart' show stroe;

Map<String, dynamic> portaal(LatLng p, double koers, List<String> stroken) => {
  'type': 'Feature',
  'properties': {'soort': 'msi', 'koers': koers, 'stroken': stroken},
  'geometry': {
    'type': 'Point',
    'coordinates': [p.longitude, p.latitude],
  },
};

void main() {
  final volger = RouteVolger(stroe());
  final punten = volger.route.punten;

  ({LatLng punt, double koers, double langs}) opRoute(int i) {
    final plek = volger.plaatsOp(punten[i]);
    return (punt: punten[i], koers: plek.koers, langs: plek.langs);
  }

  test('portalen boven jouw rijbaan, op volgorde; de overkant niet', () {
    final a = opRoute(40), b = opRoute(20);
    final portalen = portalenOpRoute(volger, {
      'features': [
        portaal(a.punt, a.koers, ['80r', 'x']),
        portaal(b.punt, b.koers, ['80r', '80r']),
        // Dezelfde plek, de andere kant op.
        portaal(a.punt, (a.koers + 180) % 360, ['50r']),
        // Ver van de route.
        portaal(const LatLng(52.5, 5.0), 0, ['50r']),
        // Op dezelfde plek, maar 30 m opzij (een parallelbaan): het portaal
        // pal boven de route wint.
        portaal(
          LatLng(b.punt.latitude + 30 / 110574, b.punt.longitude),
          b.koers,
          ['90r'],
        ),
        {
          'type': 'Feature',
          'properties': {'soort': 'ongeval'},
          'geometry': {
            'type': 'Point',
            'coordinates': [a.punt.longitude, a.punt.latitude],
          },
        },
      ],
    });
    expect(portalen.map((p) => p.stroken), [
      ['80r', '80r'],
      ['80r', 'x'],
    ]);
    expect(portalen.first.langs, closeTo(b.langs, 1));
  });

  test('de verplichte snelheid van het laatst gepasseerde portaal', () {
    const portalen = <Portaal>[
      (langs: 1000, stroken: ['80r', '80r', 'x']),
      (langs: 2000, stroken: ['70', '70']), // advies: geen limiet
      (langs: 3000, stroken: ['70r', '50r']),
      (langs: 4000, stroken: ['einde', 'einde']),
      (langs: 5000, stroken: ['90r']),
      (langs: 6000, stroken: ['', '']), // leeg: daar houdt het op
    ];
    expect(msiLimiet(portalen, 500), isNull);
    expect(msiLimiet(portalen, 1500), 80);
    expect(msiLimiet(portalen, 2500), isNull);
    expect(msiLimiet(portalen, 3500), 50); // de laagste
    expect(msiLimiet(portalen, 4500), isNull);
    expect(msiLimiet(portalen, 5500), 90);
    expect(msiLimiet(portalen, 6500), isNull);
    // Te ver na het laatste portaal: dan geldt het niet meer.
    expect(
      msiLimiet(const [
        (langs: 0, stroken: ['90r']),
      ], 3500),
      isNull,
    );
  });

  test('het volgende portaal met iets erop, binnen anderhalve kilometer', () {
    const portalen = <Portaal>[
      (langs: 1000, stroken: ['80r', 'x']),
      (langs: 2000, stroken: ['', '']),
      (langs: 3000, stroken: ['50r']),
    ];
    final eerste = volgendPortaal(portalen, 0)!;
    expect(eerste.over, 1000);
    expect(eerste.stroken, ['80r', 'x']);
    // Het lege portaal komt eerst: daarna niets tot je er langs bent.
    expect(volgendPortaal(portalen, 1200), isNull);
    expect(volgendPortaal(portalen, 2100)?.over, 900);
    expect(volgendPortaal(portalen, 3100), isNull);
    expect(
      volgendPortaal(const [
        (langs: 5000, stroken: ['50r']),
      ], 0),
      isNull,
    );
  });

  testWidgets('de matrixbalk: per strook wat erop staat', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: MatrixBalk(['80r', '70', 'x', '<', 'open', 'einde', '']),
        ),
      ),
    );
    expect(find.text('80'), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.south_west), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(find.byIcon(Icons.block), findsOneWidget);
    // Alleen de verplichte heeft een rode ring.
    final ringen = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration! as BoxDecoration).shape == BoxShape.circle,
        );
    expect(ringen, hasLength(1));
  });
}
