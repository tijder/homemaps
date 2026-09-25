// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_router.dart';

/// generated route for
/// [MapScreen]
class MapRoute extends PageRouteInfo<void> {
  const MapRoute({List<PageRouteInfo>? children})
    : super(MapRoute.name, initialChildren: children);

  static const String name = 'MapRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const MapScreen();
    },
  );
}

/// generated route for
/// [OnboardingScreen]
class OnboardingRoute extends PageRouteInfo<void> {
  const OnboardingRoute({List<PageRouteInfo>? children})
    : super(OnboardingRoute.name, initialChildren: children);

  static const String name = 'OnboardingRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const OnboardingScreen();
    },
  );
}

/// generated route for
/// [SettingsCategoryScreen]
class SettingsCategoryRoute extends PageRouteInfo<SettingsCategoryRouteArgs> {
  SettingsCategoryRoute({
    Key? key,
    required String category,
    List<PageRouteInfo>? children,
  }) : super(
         SettingsCategoryRoute.name,
         args: SettingsCategoryRouteArgs(key: key, category: category),
         rawPathParams: {'category': category},
         initialChildren: children,
       );

  static const String name = 'SettingsCategoryRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<SettingsCategoryRouteArgs>(
        orElse: () => SettingsCategoryRouteArgs(
          category: pathParams.getString('category'),
        ),
      );
      return SettingsCategoryScreen(key: args.key, category: args.category);
    },
  );
}

class SettingsCategoryRouteArgs {
  const SettingsCategoryRouteArgs({this.key, required this.category});

  final Key? key;

  final String category;

  @override
  String toString() {
    return 'SettingsCategoryRouteArgs{key: $key, category: $category}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SettingsCategoryRouteArgs) return false;
    return key == other.key && category == other.category;
  }

  @override
  int get hashCode => key.hashCode ^ category.hashCode;
}

/// generated route for
/// [SettingsScreen]
class SettingsRoute extends PageRouteInfo<SettingsRouteArgs> {
  SettingsRoute({Key? key, String? category, List<PageRouteInfo>? children})
    : super(
        SettingsRoute.name,
        args: SettingsRouteArgs(key: key, category: category),
        rawPathParams: {'category': category},
        initialChildren: children,
      );

  static const String name = 'SettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<SettingsRouteArgs>(
        orElse: () =>
            SettingsRouteArgs(category: pathParams.optString('category')),
      );
      return SettingsScreen(key: args.key, category: args.category);
    },
  );
}

class SettingsRouteArgs {
  const SettingsRouteArgs({this.key, this.category});

  final Key? key;

  final String? category;

  @override
  String toString() {
    return 'SettingsRouteArgs{key: $key, category: $category}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SettingsRouteArgs) return false;
    return key == other.key && category == other.category;
  }

  @override
  int get hashCode => key.hashCode ^ category.hashCode;
}
