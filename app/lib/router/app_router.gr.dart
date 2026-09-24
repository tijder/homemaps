// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_router.dart';

/// generated route for
/// [InstellingenCategorieScreen]
class InstellingenCategorieRoute
    extends PageRouteInfo<InstellingenCategorieRouteArgs> {
  InstellingenCategorieRoute({
    Key? key,
    required String categorie,
    List<PageRouteInfo>? children,
  }) : super(
         InstellingenCategorieRoute.name,
         args: InstellingenCategorieRouteArgs(key: key, categorie: categorie),
         rawPathParams: {'categorie': categorie},
         initialChildren: children,
       );

  static const String name = 'InstellingenCategorieRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<InstellingenCategorieRouteArgs>(
        orElse: () => InstellingenCategorieRouteArgs(
          categorie: pathParams.getString('categorie'),
        ),
      );
      return InstellingenCategorieScreen(
        key: args.key,
        categorie: args.categorie,
      );
    },
  );
}

class InstellingenCategorieRouteArgs {
  const InstellingenCategorieRouteArgs({this.key, required this.categorie});

  final Key? key;

  final String categorie;

  @override
  String toString() {
    return 'InstellingenCategorieRouteArgs{key: $key, categorie: $categorie}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InstellingenCategorieRouteArgs) return false;
    return key == other.key && categorie == other.categorie;
  }

  @override
  int get hashCode => key.hashCode ^ categorie.hashCode;
}

/// generated route for
/// [InstellingenScreen]
class InstellingenRoute extends PageRouteInfo<InstellingenRouteArgs> {
  InstellingenRoute({
    Key? key,
    String? categorie,
    List<PageRouteInfo>? children,
  }) : super(
         InstellingenRoute.name,
         args: InstellingenRouteArgs(key: key, categorie: categorie),
         rawPathParams: {'categorie': categorie},
         initialChildren: children,
       );

  static const String name = 'InstellingenRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<InstellingenRouteArgs>(
        orElse: () =>
            InstellingenRouteArgs(categorie: pathParams.optString('categorie')),
      );
      return InstellingenScreen(key: args.key, categorie: args.categorie);
    },
  );
}

class InstellingenRouteArgs {
  const InstellingenRouteArgs({this.key, this.categorie});

  final Key? key;

  final String? categorie;

  @override
  String toString() {
    return 'InstellingenRouteArgs{key: $key, categorie: $categorie}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InstellingenRouteArgs) return false;
    return key == other.key && categorie == other.categorie;
  }

  @override
  int get hashCode => key.hashCode ^ categorie.hashCode;
}

/// generated route for
/// [KaartScreen]
class KaartRoute extends PageRouteInfo<void> {
  const KaartRoute({List<PageRouteInfo>? children})
    : super(KaartRoute.name, initialChildren: children);

  static const String name = 'KaartRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const KaartScreen();
    },
  );
}
