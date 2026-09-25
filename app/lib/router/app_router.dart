import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import '../screens/map_screen.dart';
import '../screens/onboarding.dart';
import '../screens/settings/settings_screen.dart';

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
    // The first start; HomeMapsApp goes here as long as it isn't done.
    AutoRoute(page: OnboardingRoute.page, path: '/welcome'),
  ];
}
