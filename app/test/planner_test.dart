import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/models/plaats.dart';
import 'package:homemaps/providers/locatie.dart';
import 'package:homemaps/providers/planner.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'hulp/nep_bron.dart';

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

  test('een bewegende plaats vervangen brengt hem niet opnieuw in beeld', () {
    planner.toonPlaats(plaats('Partner', 52.09));
    planner.vervangPlaats(plaats('Partner', 52.10));
    expect(state().gevonden?.punt, const LatLng(52.10, 5));
    expect(state().beeldVersie, 1);
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

  test('leeg gaat terug naar een leeg zoekscherm', () {
    planner.toonPlaats(plaats('Dom', 52.09));
    planner.startRoute();
    planner.zetVan(plaats('A', 52.1));

    planner.leeg();
    expect(state().routeModus, isFalse);
    expect(state().gevonden, isNull);
    expect(namen(), [null, null]);
    expect(state().routes.value, isEmpty);
  });

  test('een route kiezen in de lijst brengt hem weer in beeld', () {
    planner.zetVan(plaats('A', 52.1), volgBeeld: false);
    final voor = state().beeldVersie;
    planner.kies(1, volgBeeld: true);
    expect(state().gekozen, 1);
    expect(state().beeldVersie, voor + 1);
    // Op de kaart aangetikt: het beeld blijft.
    planner.kies(0);
    expect(state().gekozen, 0);
    expect(state().beeldVersie, voor + 1);
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

  test(
    'met je locatie aan vertrekt een nieuwe route vanaf "Mijn locatie"',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bron = NepBron(Toestemming.ja);
      final metLocatie = ProviderContainer(
        overrides: [locatieBronProvider.overrideWithValue(bron)],
      );
      addTearDown(metLocatie.dispose);
      final wacht = metLocatie.read(locatieProvider.notifier).zetAan();
      await Future<void>.delayed(Duration.zero);
      bron.fixes.add(
        LocatieFix(punt: const LatLng(52.19, 5.7), tijd: DateTime(2026)),
      );
      await wacht;

      final p = metLocatie.read(plannerProvider.notifier);
      p.toonPlaats(plaats('Dom', 52.09));
      p.startRoute();
      final punten = metLocatie.read(plannerProvider).punten;
      expect(punten.first.plaats?.mijnLocatie, isTrue);
      expect(punten.first.plaats?.punt, const LatLng(52.19, 5.7));
      expect(punten.last.plaats?.naam, 'Dom');

      // Zocht je "Mijn locatie" zelf, dan is dat de bestemming en blijft van leeg.
      p.naarZoeken();
      p.toonPlaats(Plaats.hier(const LatLng(52.19, 5.7)));
      p.startRoute();
      expect(metLocatie.read(plannerProvider).punten.first.plaats, isNull);
    },
  );
}
