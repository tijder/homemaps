import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import '../screens/instellingen/instellingen_screen.dart';
import '../screens/kaart_screen.dart';

part 'app_router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'Screen,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: KaartRoute.page, initial: true),
    AutoRoute(page: InstellingenRoute.page, path: '/instellingen'),
    // Eén categorie, bijvoorbeeld `/instellingen/locatie-delen`; zie
    // InstellingenCategorie.pad.
    AutoRoute(
      page: InstellingenCategorieRoute.page,
      path: '/instellingen/:categorie',
    ),
  ];
}
