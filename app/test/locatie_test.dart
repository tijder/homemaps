import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/providers/instellingen.dart';
import 'package:homemaps/providers/locatie.dart';

import 'hulp/nep_bron.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container(NepBron bron) {
    final c = ProviderContainer(
      overrides: [locatieBronProvider.overrideWithValue(bron)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'toestemming: wacht op de eerste fix en onthoudt dat hij aan staat',
    () async {
      final bron = NepBron(Toestemming.ja);
      final c = container(bron);
      final wacht = c.read(locatieProvider.notifier).zetAan();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(locatieProvider).stand, LocatieStand.zoekt);
      bron.fixes.add(fix(52.1));
      expect((await wacht)?.punt.latitude, 52.1);
      expect(c.read(locatieProvider).stand, LocatieStand.aan);
      expect(c.read(instellingenProvider).locatieAan, isTrue);
      // Een tweede tik vraagt niet opnieuw.
      await c.read(locatieProvider.notifier).zetAan();
      expect(bron.gevraagd, 1);
    },
  );

  test('geweigerd en nooit: geen fix, en de reden in de toestand', () async {
    final bron = NepBron(Toestemming.nee);
    final c = container(bron);
    expect(await c.read(locatieProvider.notifier).zetAan(), isNull);
    expect(c.read(locatieProvider).stand, LocatieStand.geweigerd);
    bron.antwoord = Toestemming.nooit;
    expect(await c.read(locatieProvider.notifier).zetAan(), isNull);
    expect(c.read(locatieProvider).stand, LocatieStand.permanentGeweigerd);
    expect(c.read(instellingenProvider).locatieAan, isFalse);
  });

  test('uitzetten wist de fix en de instelling', () async {
    final bron = NepBron(Toestemming.ja);
    final c = container(bron);
    final wacht = c.read(locatieProvider.notifier).zetAan();
    await Future<void>.delayed(Duration.zero);
    bron.fixes.add(fix(52.1));
    await wacht;
    c.read(locatieProvider.notifier).zetUit();
    expect(c.read(locatieProvider).fix, isNull);
    expect(c.read(instellingenProvider).locatieAan, isFalse);
  });

  test(
    'navigatie start de stroom opnieuw, nauwkeurig en met melding',
    () async {
      final bron = NepBron(Toestemming.ja);
      final c = container(bron);
      final wacht = c.read(locatieProvider.notifier).zetAan();
      await Future<void>.delayed(Duration.zero);
      bron.fixes.add(fix(52.1));
      await wacht;
      expect(bron.laatsteNauwkeurig, isFalse);
      c.read(locatieProvider.notifier).navigatie((
        titel: 'Navigatie',
        tekst: 'x',
      ));
      expect(bron.laatsteNauwkeurig, isTrue);
      expect(bron.laatsteMelding?.titel, 'Navigatie');
    },
  );
}
