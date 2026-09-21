import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/models/plaats.dart';
import 'package:homemaps/providers/planner.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

Plaats plaats(String naam, double lat) =>
    Plaats(naam: naam, punt: LatLng(lat, 5));

void main() {
  late ProviderContainer container;
  late PlannerNotifier planner;
  PlannerState state() => container.read(plannerProvider);
  List<String?> namen() => [for (final p in state().punten) p.plaats?.naam];

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    planner = container.read(plannerProvider.notifier);
  });

  test('zoeken eerst: een plaats kiezen opent nog geen route', () {
    planner.toonPlaats(plaats('Dom', 52.09));
    expect(state().routeModus, isFalse);
    expect(state().gevonden?.naam, 'Dom');
    expect(state().beeldVersie, 1);

    planner.startRoute();
    expect(state().routeModus, isTrue);
    expect(namen(), [null, 'Dom']);

    planner.naarZoeken();
    expect(state().routeModus, isFalse);
    expect(state().gevonden?.naam, 'Dom');
    expect(namen(), [null, null]);
  });

  test('rechtermuisknop gaat direct naar het routescherm', () {
    planner.zetVan(plaats('A', 52.1), volgBeeld: false);
    expect(state().routeModus, isTrue);
    expect(state().beeldVersie, 0);
    planner.zetNaar(plaats('B', 52.2));
    expect(namen(), ['A', 'B']);
  });

  test('verplaatsen houdt het id bij de plaats', () {
    planner.zetVan(plaats('A', 52.1));
    planner.voegViaToe(plaats('B', 52.2));
    planner.zetNaar(plaats('C', 52.3));
    final idVanC = state().punten.last.id;

    planner.verplaats(2, 0); // C naar voren
    expect(namen(), ['C', 'A', 'B']);
    expect(state().punten.first.id, idVanC);

    planner.verplaats(0, 1); // C een plek omlaag
    expect(namen(), ['A', 'C', 'B']);

    planner.draaiOm();
    expect(namen(), ['B', 'C', 'A']);
  });

  test('verwijderen: een via verdwijnt, van en naar worden leeg', () {
    planner.zetVan(plaats('A', 52.1));
    planner.voegViaToe(plaats('B', 52.2));
    planner.verwijder(1);
    expect(namen(), ['A', null]);
    planner.verwijder(0);
    expect(namen(), [null, null]);
  });

  test('hernoemen verandert de naam, niet de volgorde of de ids', () {
    planner.zetVan(Plaats.vanPunt(const LatLng(52.1, 5)));
    final id = state().punten.first.id;
    planner.hernoem(0, plaats('Domplein 1', 52.1));
    expect(namen(), ['Domplein 1', null]);
    expect(state().punten.first.id, id);
  });
}
