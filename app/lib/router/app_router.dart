import 'package:auto_route/auto_route.dart';

import '../screens/dawarich_screen.dart';
import '../screens/instellingen_screen.dart';
import '../screens/kaart_screen.dart';
import '../screens/locatie_delen_screen.dart';
import '../screens/over_screen.dart';

part 'app_router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'Screen,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: KaartRoute.page, initial: true),
    AutoRoute(page: InstellingenRoute.page, path: '/instellingen'),
    AutoRoute(
      page: LocatieDelenRoute.page,
      path: '/instellingen/locatie-delen',
    ),
    AutoRoute(page: DawarichRoute.page, path: '/instellingen/dawarich'),
    AutoRoute(page: OverRoute.page, path: '/instellingen/over'),
  ];
}
