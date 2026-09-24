import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/router/app_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('de router start, en een categorie heeft een eigen adres', () {
    // auto_route controleert pas bij het opbouwen of elke route een eigen
    // naam heeft; dan zou de app bij het starten al vallen.
    final router = AppRouter();
    expect(router.config, returnsNormally);

    final lijst = router.matcher.match('/instellingen');
    expect(lijst?.single.name, InstellingenRoute.name);

    final categorie = router.matcher.match('/instellingen/locatie-delen');
    expect(categorie?.single.name, InstellingenCategorieRoute.name);
    expect(categorie?.single.params.optString('categorie'), 'locatie-delen');
  });
}
