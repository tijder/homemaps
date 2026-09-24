import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import '../screens/settings/settings_screen.dart';
import '../screens/map_screen.dart';

part 'app_router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'Screen,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: MapRoute.page, initial: true),
    AutoRoute(page: SettingsRoute.page, path: '/settings'),
    // One category, for example `/settings/location-sharing`; see
    // SettingsCategory.path.
    AutoRoute(page: SettingsCategoryRoute.page, path: '/settings/:category'),
  ];
}
