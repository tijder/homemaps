import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/models/profiel.dart';
import 'package:homemaps/services/valhalla_service.dart';
import 'package:homemaps/utils/polyline.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  const a = LatLng(52.09, 5.12), b = LatLng(52.2, 5.0), c = LatLng(52.37, 4.89);

  test('twee punten: alternatieven en live verkeer voor de auto', () {
    final v = ValhallaService.verzoek([a, c], Profiel.auto, taal: 'nl-NL');
    expect(v['alternates'], 2);
    expect(v['date_time'], {'type': 0});
    expect(v['costing'], 'auto');
    expect((v['locations'] as List).map((l) => l['type']), ['break', 'break']);
  });

  test('via-punten: geen alternatieven, tussenpunt is through', () {
    final v = ValhallaService.verzoek([a, b, c], Profiel.auto, taal: 'nl-NL');
    expect(v.containsKey('alternates'), isFalse);
    expect((v['locations'] as List).map((l) => l['type']), [
      'break',
      'through',
      'break',
    ]);
  });

  test('fiets krijgt geen live verkeer; vermijden wordt een costing-optie', () {
    final fiets = ValhallaService.verzoek([a, c], Profiel.fiets, taal: 'nl-NL');
    expect(fiets.containsKey('date_time'), isFalse);
    final auto = ValhallaService.verzoek(
      [a, c],
      Profiel.auto,
      taal: 'nl-NL',
      vermijdSnelwegen: true,
      vermijdVeren: true,
    );
    expect(auto['costing_options'], {
      'auto': {'use_highways': 0.0, 'use_ferry': 0.0},
    });
  });

  test('polyline met zes decimalen', () {
    // Utrecht -> Amsterdam, gecodeerd met precisie 6 (Google's formaat kent 5).
    final punten = decodeerPolyline('wsjjbBovqwH_qfP~s~L');
    expect(punten, hasLength(2));
    expect(punten[0].latitude, closeTo(52.0907, 1e-9));
    expect(punten[0].longitude, closeTo(5.1214, 1e-9));
    expect(punten[1].latitude, closeTo(52.3731, 1e-9));
    expect(punten[1].longitude, closeTo(4.8922, 1e-9));
  });

  test('antwoord met alternatief, twee legs en hoogte', () {
    Map<String, dynamic> trip(double km, List<Map<String, dynamic>> legs) => {
      'summary': {
        'length': km,
        'time': km * 60,
        'has_toll': false,
        'has_ferry': true,
      },
      'legs': legs,
    };
    final leg = {
      'shape': 'wsjjbBovqwH_qfP~s~L',
      'elevation': [10, 14, 12],
      'maneuvers': [
        {
          'instruction': 'Rijd naar het noorden.',
          'type': 1,
          'length': 1.5,
          'time': 90,
          'begin_shape_index': 0,
        },
        {
          'instruction': 'U bent aangekomen.',
          'type': 4,
          'length': 0,
          'time': 0,
          'begin_shape_index': 1,
        },
      ],
    };
    final routes = ValhallaService.leesAntwoord({
      'trip': trip(12.5, [leg, leg]),
      'alternates': [
        {
          'trip': trip(15, [leg]),
        },
      ],
    });
    expect(routes, hasLength(2));
    expect(routes[0].meters, 12500);
    expect(routes[0].punten, hasLength(4));
    // De tweede leg telt door in de vorm.
    expect(routes[0].manoeuvres[2].vormIndex, 2);
    expect(routes[0].hoogtes, [10, 14, 12, 10, 14, 12]);
    expect(routes[0].stijging, 8);
    expect(routes[0].daling, 6);
    expect(routes[0].heeftVeer, isTrue);
    expect(routes[1].meters, 15000);
  });
}
