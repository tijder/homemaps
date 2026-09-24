import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/router/app_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the router starts, and a category has its own address', () {
    // auto_route only checks on build whether every route has its own
    // name; the app would then already crash at startup.
    final router = AppRouter();
    expect(router.config, returnsNormally);

    final list = router.matcher.match('/settings');
    expect(list?.single.name, SettingsRoute.name);

    final category = router.matcher.match('/settings/location-sharing');
    expect(category?.single.name, SettingsCategoryRoute.name);
    expect(category?.single.params.optString('category'), 'location-sharing');
  });
}
