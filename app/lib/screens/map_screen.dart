import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../l10n/app_localizations.dart';
import '../models/dawarich.dart';
import '../models/place.dart';
import '../models/profile.dart';
import '../models/route.dart';
import '../navigation/turn_arrow.dart';
import '../navigation/navigation_provider.dart';
import '../navigation/simulation.dart';
import '../providers/dawarich.dart';
import '../providers/services.dart';
import '../providers/settings.dart';
import '../providers/location.dart';
import '../providers/location_sharing.dart';
import '../providers/planner.dart';
import '../providers/saved_places.dart';
import '../utils/distance.dart';
import '../utils/geo_link.dart';
import '../utils/formatting.dart' show timeAgo;
import '../router/app_router.dart';
import 'settings/category.dart';
import '../utils/mouse_stub.dart'
    if (dart.library.js_interop) '../utils/mouse_web.dart';
import '../utils/test_hook_stub.dart'
    if (dart.library.js_interop) '../utils/test_hook_web.dart';
import '../widgets/step_list.dart';
import '../widgets/map_widget.dart';
import '../widgets/along_route_search.dart';
import '../widgets/location_reason.dart';
import '../widgets/navigation_bar.dart';
import '../widgets/route_panel.dart';
import '../widgets/traffic_incident.dart';
import '../widgets/search_field.dart';

@RoutePage()
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _panelWidth = 380.0;

  /// The choices in the layers menu that turn the traffic layer and your
  /// location on or off.
  static const _traffic = 'traffic';
  static const _location = 'location';

  /// Choices for day or night with the "Map" style: `theme:` + [MapTheme].
  static const _theme = 'theme:';

  MapLibreMapController? _map;
  ({Offset position, LatLng point})? _menu;
  ({Offset position, Map<String, dynamic> info})? _incident;
  late final void Function() _stopMouse;

  /// During navigation: does the camera follow along? Not for a while when you
  /// touch the map yourself; again after [_resumeAfter] without a touch.
  bool _following = true;
  Timer? _resume;
  static const _resumeAfter = Duration(seconds: 10);

  /// This close to the next turn the arrow shows on the map.
  static const _arrowWithin = 1000.0;

  /// The arrow of the last turn; only a new one for another turn or route, so
  /// the map doesn't redraw it on every fix.
  ({RouteOption route, int index, List<LatLng>? line})? _arrow;

  /// The bottom sheet on a narrow screen: low (just the summary and the chosen
  /// route), half (all routes and Start) or almost full.
  final _sheet = DraggableScrollableController();
  static const _sheetHalf = 0.45, _sheetFull = 0.92;
  double _sheetFraction = _sheetHalf;

  /// Tall enough for the handle, the summary line and one route.
  double _sheetLow(double height) => (205 / height).clamp(0.12, 0.3);

  /// With the screen off (navigation keeps running) following along is pointless.
  bool _visible = true;
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<Uri>? _links;

  LatLng? _center() => _map?.cameraPosition?.target;

  /// The card of the followed family member; while it's open, the map follows
  /// them.
  Place? _familyPlace;

  /// You moved the map yourself: the card keeps updating, the camera doesn't,
  /// until "Follow".
  bool _familyDetached = false;

  Place _asPlace(FamilyLocation member, AppLocalizations l) => Place(
    label: member.email,
    description: [
      timeAgo(l, DateTime.now().difference(member.time)),
      if (member.battery case final percent?) l.familyBattery(percent),
    ].join(' · '),
    point: member.point,
  );

  /// Tapped a family member: their card, and the map follows them.
  void _followFamily(FamilyLocation member) {
    final place = _asPlace(member, AppLocalizations.of(context));
    setState(() {
      _familyPlace = place;
      _familyDetached = false;
    });
    ref.read(followedMemberProvider.notifier).follow(member.userId);
    ref.read(plannerProvider.notifier).showPlace(place);
  }

  void _stopFamily() {
    _familyPlace = null;
    ref.read(followedMemberProvider.notifier).stop();
  }

  /// New family locations: update the followed member.
  void _familyUpdated(List<FamilyLocation> family) {
    final id = ref.read(followedMemberProvider);
    if (id == null) return;
    final member = family.where((f) => f.userId == id).firstOrNull;
    // No longer sharing, or family is turned off.
    if (member == null) {
      _stopFamily();
      return;
    }
    final place = _asPlace(member, AppLocalizations.of(context));
    _familyPlace = place;
    ref.read(plannerProvider.notifier).replacePlace(place);
    if (!_familyDetached) {
      _map?.animateCamera(CameraUpdate.newLatLng(member.point));
    }
  }

  @override
  void initState() {
    super.initState();
    _stopMouse = attachMouse((onMap, onScreen) async {
      final point = await _map?.toLatLng(onMap);
      if (point != null && mounted) _pointMenu(onScreen, point);
    }, onTouch: _userMoved);
    // An address or point from another app (calendar, contacts, a website):
    // `geo:` and `google.navigation:`. Also the link the app was started with.
    if (!kIsWeb) _links = AppLinks().uriLinkStream.listen(_linkReceived);
    // On the web: ?to=lat,lon (and optionally &from=lat,lon) opens the route
    // right away, to share a route as a link. With ?simulate= the location
    // also turns on by itself (for the browser tests).
    if (kIsWeb) WidgetsBinding.instance.addPostFrameCallback((_) => _fromUrl());
    _lifecycle = AppLifecycleListener(
      onHide: () => setState(() => _visible = false),
      onShow: () => setState(() => _visible = true),
    );
  }

  @override
  void dispose() {
    _stopMouse();
    _resume?.cancel();
    _lifecycle.dispose();
    _links?.cancel();
    _sheet.dispose();
    super.dispose();
  }

  Future<void> _fromUrl() async {
    final parameters = Uri.base.queryParameters;
    LatLng? point(String? text) {
      final parts = text?.split(',');
      if (parts == null || parts.length != 2) return null;
      final lat = double.tryParse(parts[0]), lon = double.tryParse(parts[1]);
      return lat == null || lon == null ? null : LatLng(lat, lon);
    }

    if (ref.read(locationSourceProvider) is SimulationSource) {
      await ref.read(locationProvider.notifier).turnOn();
    }
    final to = point(parameters['to']);
    if (to == null || !mounted) return;
    final planner = ref.read(plannerProvider.notifier);
    planner.showPlace(Place.fromPoint(to));
    planner.startRoute();
    if (point(parameters['from']) case final from?) {
      planner.setFrom(Place.fromPoint(from));
    }
  }

  void _userMoved() {
    if (_familyPlace != null && !_familyDetached) {
      setState(() => _familyDetached = true);
    }
    if (ref.read(navigationProvider) == null) return;
    _resume?.cancel();
    _resume = Timer(_resumeAfter, () {
      if (mounted) setState(() => _following = true);
    });
    if (_following) setState(() => _following = false);
  }

  /// "Start": location on if needed, then navigate to the points after "from".
  /// If "from" is somewhere other than you, navigation recalculates by itself
  /// from where you are.
  Future<void> _startNavigation(RouteOption route) async {
    final l = AppLocalizations.of(context);
    // The button only works with a known position; see RoutePanel.
    if (ref.read(locationProvider).fix == null) {
      _reportLocationProblem();
      return;
    }
    final destinations = [
      for (final point in ref.read(plannerProvider).points.skip(1))
        ?point.place,
    ];
    if (destinations.isEmpty) return;
    // Android 13+: without this permission navigation with the screen off still
    // runs, but without a visible notification. Ask once; refusing is fine.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Permission.notification.request();
      if (!mounted) return;
    }
    setState(() => _following = true);
    await ref
        .read(navigationProvider.notifier)
        .start(
          route: route,
          destinations: destinations,
          texts: NavTexts.of(
            l,
            ref.read(plannerProvider.notifier).language,
            destinations.last.display(l),
            sharing: ref.read(shareSettingsProvider).enabled,
          ),
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Valhalla knows 'nl-NL' and 'en-US'; everything else falls back to English.
    final language = Localizations.localeOf(context).languageCode;
    ref.read(plannerProvider.notifier).language = language == 'nl'
        ? 'nl-NL'
        : 'en-US';
  }

  /// The "from here / to here / as stop" menu: right mouse button on the web,
  /// long press on Android. No showMenu: on the web the map is a separate HTML
  /// element that captures the mouse, so Flutter's own menu never saw the click
  /// next to it -- it didn't close, and every right click added another one.
  /// This is one piece of state, so there's always at most one.
  void _pointMenu(Point<double> screen, LatLng point) => setState(
    () => _menu = (position: Offset(screen.x, screen.y), point: point),
  );

  Future<void> _choose(String action, LatLng point) async {
    setState(() => _menu = null);
    final planner = ref.read(plannerProvider.notifier);
    // No moveView: you clicked on the map, so the point is already in view.
    switch (action) {
      case 'from':
        planner.setFrom(Place.fromPoint(point), moveView: false);
      case 'to':
        planner.setTo(Place.fromPoint(point), moveView: false);
      default:
        planner.addVia(Place.fromPoint(point));
    }
    await _lookUpAddress(point);
  }

  /// A point placed or dragged on the map is first named after its coordinates,
  /// so the route is calculated right away; the address is added once Photon
  /// answers -- or not, and then it stays coordinates.
  Future<void> _lookUpAddress(LatLng point) async {
    try {
      final withAddress = await ref.read(photonProvider)?.reverseGeocode(point);
      if (withAddress == null || !mounted) return;
      final points = ref.read(plannerProvider).points;
      final index = points.indexWhere((p) => p.place?.point == point);
      if (index < 0) return; // moved again in the meantime
      // Only the name changes; the route doesn't need recalculating.
      ref.read(plannerProvider.notifier).rename(index, withAddress);
    } on Object {
      // No address is not an error.
    }
  }

  /// North up and flat: `bearingTo(0)` alone leaves a tilted map tilted.
  /// Position and zoom stay as they are.
  void _resetNorth() {
    final now = _map?.cameraPosition;
    if (now == null) return;
    _map!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: now.target, zoom: now.zoom, bearing: 0, tilt: 0),
      ),
    );
  }

  /// The "My location" button: asks for permission if needed and flies there.
  Future<void> _toMyLocation() async {
    final fix = await ref.read(locationProvider.notifier).turnOn();
    if (!mounted) return;
    if (fix == null) {
      _reportLocationProblem();
      return;
    }
    final zoom = max(_map?.cameraPosition?.zoom ?? 0, 15.0);
    await _map?.animateCamera(CameraUpdate.newLatLngZoom(fix.point, zoom));
  }

  Future<void> _linkReceived(Uri uri) async {
    final request = parseGeoLink(uri);
    if (request == null || !mounted) return;
    final l = AppLocalizations.of(context);
    if (ref.read(navigationProvider) != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.stopFirst)));
      return;
    }
    Place? place;
    if (request.point case final point?) {
      place = request.label == null
          ? Place.fromPoint(point)
          : Place(label: request.label!, point: point);
    } else if (request.search case final search?) {
      try {
        final found = await ref
            .read(photonProvider)
            ?.search(
              search,
              near: ref.read(locationProvider).fix?.point ?? _center(),
            );
        place = found?.firstOrNull;
      } on Object {
        place = null;
      }
      if (!mounted) return;
      if (place == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.notFound(search))));
        return;
      }
    }
    if (place == null) return;
    final planner = ref.read(plannerProvider.notifier);
    planner.toSearch();
    planner.showPlace(place);
    if (request.navigate) planner.startRoute();
    // A bare point gets its address once Photon knows it.
    if (request.point != null && request.label == null) {
      try {
        final withAddress = await ref
            .read(photonProvider)
            ?.reverseGeocode(place.point);
        if (withAddress != null && mounted) {
          final now = ref.read(plannerProvider);
          if (now.found?.point == place.point && !now.routeMode) {
            planner.showPlace(withAddress);
          }
        }
      } on Object {
        // Then it stays coordinates.
      }
    }
  }

  /// Location on from the route panel (for navigation): without moving the
  /// map.
  Future<void> _turnOnLocation() async {
    final fix = await ref.read(locationProvider.notifier).turnOn();
    if (fix == null && mounted) _reportLocationProblem();
  }

  /// "My location" in a search field.
  Future<Place?> _myLocationAsPlace() async {
    final fix = await ref.read(locationProvider.notifier).turnOn();
    if (!mounted) return null;
    if (fix == null) {
      _reportLocationProblem();
      return null;
    }
    return Place.here(fix.point);
  }

  /// Why there is no location, and where to fix that. On the web the app can't
  /// open the browser's settings; then just the explanation. iOS only opens the
  /// app's own settings, not the location settings.
  void _reportLocationProblem() {
    final l = AppLocalizations.of(context);
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final status = ref.read(locationProvider).status;
    final text = locationReason(l, status) ?? l.locationNotFound;
    final onOpen = switch (status) {
      LocationStatus.permanentlyDenied when android || ios =>
        Geolocator.openAppSettings,
      LocationStatus.serviceOff when android => Geolocator.openLocationSettings,
      _ => null,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        action: onOpen == null
            ? null
            : SnackBarAction(label: l.settings, onPressed: onOpen),
      ),
    );
  }

  void _dragged(int index, LatLng point) {
    ref
        .read(plannerProvider.notifier)
        .setPoint(index, Place.fromPoint(point), moveView: false);
    _lookUpAddress(point);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final config = ref.watch(appConfigProvider);
    if (config == null) return const _ServerRequired();

    // The map can only get its initial position once; briefly waiting for the
    // TileJSON (at most 5 s) beats opening above the wrong country.
    final start = ref.watch(mapStartProvider).value;
    if (start == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    ref.listen(familyLocationsProvider, (_, family) {
      _familyUpdated(family);
    });
    // Another card, or a route: stop following.
    ref.listen(plannerProvider, (_, p) {
      if (_familyPlace != null &&
          (p.routeMode || !identical(p.found, _familyPlace))) {
        _stopFamily();
      }
    });

    final planner = ref.watch(plannerProvider);
    final settings = ref.watch(settingsProvider);
    final locationStatus = ref.watch(locationProvider.select((t) => t.status));
    final locationEnabled =
        locationStatus == LocationStatus.enabled ||
        locationStatus == LocationStatus.searching ||
        locationStatus == LocationStatus.notFound;
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final height = MediaQuery.sizeOf(context).height;

    final nav = ref.watch(navigationProvider);
    final fix = ref.watch(locationProvider.select((t) => t.fix));
    if (kIsWeb && ref.read(locationSourceProvider) is SimulationSource) {
      final status = nav?.status;
      publishTestState({
        'location': ref.read(locationProvider).status.name,
        'routeMode': planner.routeMode,
        'routes': planner.routes.value?.length ?? 0,
        'navigating': nav != null,
        'arrived': nav?.arrived ?? false,
        'next': status == null
            ? null
            : nav!.route.maneuvers[status.next].instruction,
        'remainingMeters': status?.remainingMeters.round(),
        'offRoute': status?.offRoute,
      });
    }
    // During navigation the dot sits on the road as long as you drive on the
    // route, as you're used to from a navigation system.
    final status = nav?.status;
    final onRoad =
        nav != null && status != null && fix != null && status.deviation < 30
        ? LocationFix(
            point: status.onRoute,
            time: fix.time,
            accuracy: fix.accuracy,
            heading: status.routeHeading,
            speed: fix.speed,
          )
        : fix;

    // At night (fixed, or when the phone is in dark mode) the night version of
    // the regular map. Until it's there (or if it fails) the regular one.
    final styleUrl = config.styleUrl(settings.style);
    final isNight = switch (settings.theme) {
      MapTheme.automatic =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
      MapTheme.day => false,
      MapTheme.night => true,
    };
    final night = settings.style == MapStyle.map.id && isNight
        ? ref.watch(nightStyleProvider(styleUrl)).value
        : null;
    final map = MapWidget(
      styleUrl: night ?? styleUrl,
      start: start,
      points: nav != null
          ? [null, ...nav.destinations]
          : [for (final point in planner.points) point.place],
      found: nav != null ? null : planner.found,
      viewVersion: planner.viewVersion,
      onPointDragged: nav != null ? (_, _) {} : _dragged,
      // During navigation the route, and a suggested faster one in grey next to it.
      routes: nav != null
          ? [nav.route, ?nav.suggestion?.route]
          : planner.routes.value ?? const [],
      chosen: nav != null ? 0 : planner.chosen,
      onRouteChosen: nav != null
          // Tapping the grey line is "Take".
          ? (i) {
              if (i == 1) {
                ref.read(navigationProvider.notifier).acceptSuggestion();
              }
            }
          : ref.read(plannerProvider.notifier).choose,
      onLongPress: _pointMenu,
      onController: (controller) => _map = controller,
      location: onRoad,
      follow:
          nav != null &&
              _following &&
              _visible &&
              onRoad != null &&
              !nav.arrived
          ? (
              point: onRoad.point,
              heading: onRoad.heading ?? status?.routeHeading ?? 0,
              speed: onRoad.speed ?? 0,
            )
          : null,
      navigating: nav != null && !nav.arrived,
      driven: nav != null && status != null
          ? [...nav.route.points.take(status.segment + 1), status.onRoute]
          : null,
      arrow: _arrowFor(nav),
      onUserMoved: _userMoved,
      traffic: ref.watch(trafficProvider).value,
      // A traffic jam means nothing to cyclists and walkers; a closed road does.
      showDelay: settings.profile == Profile.car,
      onTrafficTapped: (screen, info) => setState(
        () => _incident = (position: Offset(screen.x, screen.y), info: info),
      ),
      family: ref.watch(familyLocationsProvider),
      // A family member is a place like a search result, with "Route" to it,
      // and the map follows them.
      onFamilyTapped: nav != null ? null : _followFamily,
      padding: wide
          ? const EdgeInsets.only(left: _panelWidth)
          : EdgeInsets.only(
              top: planner.routeMode ? 0 : 72,
              bottom: planner.routeMode ? height * _sheetFraction : 0,
            ),
    );

    final buttons = SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: PointerInterceptor(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<String>(
                  tooltip: l.mapStyle,
                  icon: const _RoundIcon(Icons.layers_outlined),
                  initialValue: settings.style,
                  onSelected: (choice) {
                    if (choice == _location) {
                      locationEnabled
                          ? ref.read(locationProvider.notifier).turnOff()
                          : _toMyLocation();
                      return;
                    }
                    ref
                        .read(settingsProvider.notifier)
                        .modify(
                          choice == _traffic
                              ? settings.copyWith(
                                  trafficOnMap: !settings.trafficOnMap,
                                )
                              : choice.startsWith(_theme)
                              ? settings.copyWith(
                                  theme: MapTheme.values.byName(
                                    choice.substring(_theme.length),
                                  ),
                                )
                              : settings.copyWith(style: choice),
                        );
                  },
                  itemBuilder: (_) => [
                    for (final style in MapStyle.values)
                      PopupMenuItem(
                        value: style.id,
                        child: PointerInterceptor(child: Text(style.label(l))),
                      ),
                    if (settings.style == MapStyle.map.id) ...[
                      const PopupMenuDivider(),
                      for (final theme in MapTheme.values)
                        CheckedPopupMenuItem(
                          value: '$_theme${theme.name}',
                          checked: settings.theme == theme,
                          child: PointerInterceptor(
                            child: Text(theme.label(l)),
                          ),
                        ),
                    ],
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem(
                      value: _traffic,
                      checked: settings.trafficOnMap,
                      child: PointerInterceptor(child: Text(l.trafficOnMap)),
                    ),
                    CheckedPopupMenuItem(
                      value: _location,
                      checked: locationEnabled,
                      child: PointerInterceptor(child: Text(l.myLocation)),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: l.myLocation,
                  icon: _RoundIcon(switch (locationStatus) {
                    LocationStatus.enabled => Icons.my_location,
                    LocationStatus.off ||
                    LocationStatus.searching => Icons.location_searching,
                    LocationStatus.notFound => Icons.gps_not_fixed,
                    _ => Icons.location_disabled,
                  }),
                  onPressed: _toMyLocation,
                ),
                IconButton(
                  tooltip: l.northUp,
                  icon: const _RoundIcon(Icons.explore_outlined),
                  onPressed: _resetNorth,
                ),
                IconButton(
                  tooltip: l.settings,
                  icon: const _RoundIcon(Icons.settings_outlined),
                  onPressed: () => context.router.push(SettingsRoute()),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final menu = _menu == null ? null : _menuOverlay(context, _menu!);
    final notification = _incident == null
        ? null
        : _incidentOverlay(context, _incident!.position, _incident!.info);

    // May the back button leave the app? Only if there's nothing left to close.
    final canLeave =
        nav == null &&
        !planner.routeMode &&
        planner.found == null &&
        _menu == null &&
        _incident == null;
    Widget backButton(Widget child) => PopScope(
      canPop: canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: child,
    );

    if (nav != null) {
      return backButton(
        Scaffold(
          body: Stack(
            children: [map, _navigationOverlay(nav, wide), ?notification],
          ),
        ),
      );
    }

    return backButton(
      Scaffold(
        body: Stack(
          children: [
            map,
            // On a narrow screen the search bar is at the top; the buttons move
            // below it. Before the panels in the stack: the search bar's
            // suggestions and the pulled-up sheet go over them, not under.
            Padding(
              padding: EdgeInsets.only(
                top: !wide && !planner.routeMode ? 64 : 0,
              ),
              child: buttons,
            ),
            if (!planner.routeMode)
              _searchScreen(context, planner, wide)
            else if (wide)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _panelWidth,
                // On the web the map is a separate HTML element below Flutter.
                // Without an interceptor its drag cursor shows through the panel.
                child: PointerInterceptor(
                  child: Material(
                    elevation: 4,
                    child: SafeArea(
                      child: RoutePanel(
                        near: _center,
                        myLocation: _myLocationAsPlace,
                        onNavigate: _startNavigation,
                        onEnableLocation: _turnOnLocation,
                      ),
                    ),
                  ),
                ),
              )
            else
              NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  // For bringing the route into view: above the sheet.
                  _sheetFraction = notification.extent;
                  // Swiped all the way down: closed, back to search.
                  if (notification.extent < 0.02) _closeSheet();
                  return false;
                },
                child: DraggableScrollableSheet(
                  controller: _sheet,
                  initialChildSize: _sheetHalf,
                  // Below the low position is closed: the sheet can follow
                  // down to 0, and then it closes.
                  minChildSize: 0,
                  maxChildSize: _sheetFull,
                  snap: true,
                  snapSizes: [_sheetLow(height), _sheetHalf],
                  builder: (context, scroll) => PointerInterceptor(
                    child: Material(
                      elevation: 8,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _handle(height),
                          Expanded(
                            // Draggable with the mouse too (a narrow browser
                            // window); by default Flutter only allows that with
                            // a finger.
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(
                                    dragDevices: {
                                      ...ScrollConfiguration.of(context)
                                          .dragDevices,
                                      PointerDeviceKind.mouse,
                                    },
                                  ),
                              child: RoutePanel(
                                near: _center,
                                myLocation: _myLocationAsPlace,
                                onNavigate: _startNavigation,
                                onEnableLocation: _turnOnLocation,
                                scroll: scroll,
                                compact: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ?notification,
            ?menu,
          ],
        ),
      ),
    );
  }

  /// The start screen: one search bar, and after a choice a card of the place
  /// with the "Route" button. Only that button opens the route screen.
  Widget _searchScreen(BuildContext context, PlannerState planner, bool wide) {
    final l = AppLocalizations.of(context);
    final actions = ref.read(plannerProvider.notifier);
    final found = planner.found;
    final bar = PointerInterceptor(
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SearchField(
            floating: true,
            label: l.searchHere,
            icon: Icons.search,
            place: found,
            near: _center,
            onChosen: actions.showPlace,
            myLocation: _myLocationAsPlace,
            onCleared: actions.closePlace,
          ),
        ),
      ),
    );
    final card = found == null
        ? null
        : PointerInterceptor(
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(16),
              // Full width: the interceptor around it doesn't pass on the
              // column's width, and then the card shrinks to its text.
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      found.display(l),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (found.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(found.description),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: actions.startRoute,
                          icon: const Icon(Icons.directions),
                          label: Text(l.route),
                        ),
                        if (identical(found, _familyPlace))
                          _familyDetached
                              ? OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() => _familyDetached = false);
                                    _map?.animateCamera(
                                      CameraUpdate.newLatLng(found.point),
                                    );
                                  },
                                  icon: const Icon(Icons.my_location),
                                  label: Text(l.familyFollow),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.my_location, size: 18),
                                    const SizedBox(width: 4),
                                    Text(l.familyFollowing),
                                  ],
                                )
                        else if (!found.myLocation) ...[
                          _SaveButton(
                            place: found,
                            current: ref.watch(savedPlacesProvider).home,
                            icon: Icons.home_outlined,
                            label: l.asHome,
                            savedLabel: l.home,
                            onSave: ref
                                .read(savedPlacesProvider.notifier)
                                .setHome,
                          ),
                          _SaveButton(
                            place: found,
                            current: ref.watch(savedPlacesProvider).work,
                            icon: Icons.work_outline,
                            label: l.asWork,
                            savedLabel: l.work,
                            onSave: ref
                                .read(savedPlacesProvider.notifier)
                                .setWork,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: wide
            ? Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: _panelWidth - 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [bar, const SizedBox(height: 12), ?card],
                  ),
                ),
              )
            // Narrow: the bar on top, the card below -- the map in between
            // stays clear.
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [bar, const Spacer(), ?card],
              ),
      ),
    );
  }

  /// A plane over the whole screen that keeps the mouse off the map, with the
  /// menu on it. Clicking next to it closes it; right-clicking next to it moves it.
  Widget _menuOverlay(
    BuildContext context,
    ({Offset position, LatLng point}) menu,
  ) {
    final l = AppLocalizations.of(context);
    final screen = MediaQuery.sizeOf(context);
    const width = 220.0, height = 3 * 48.0 + 16;
    return Positioned.fill(
      child: PointerInterceptor(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _menu = null),
          onSecondaryTapDown: (details) async {
            // This plane lies exactly over the map, so the position on it is also
            // the position on the map.
            final position = Point(
              details.localPosition.dx,
              details.localPosition.dy,
            );
            final point = await _map?.toLatLng(position);
            if (point != null && mounted) _pointMenu(position, point);
          },
          child: Stack(
            children: [
              Positioned(
                // Stay on screen, even for a click in the corner.
                left: min(menu.position.dx, screen.width - width - 8),
                top: min(menu.position.dy, screen.height - height - 8),
                width: width,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (action, icon, text) in [
                          ('from', Icons.trip_origin, l.directionsFrom),
                          ('to', Icons.place, l.directionsTo),
                          ('via', Icons.more_vert, l.asStop),
                        ])
                          ListTile(
                            dense: true,
                            leading: Icon(icon),
                            title: Text(text),
                            onTap: () => _choose(action, menu.point),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _closeScheduled = false;

  /// The sheet was swiped closed: back to search after this frame (not during
  /// the notification itself, the sheet is still being built then).
  void _closeSheet() {
    if (_closeScheduled) return;
    _closeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _closeScheduled = false;
      if (!mounted) return;
      _sheetFraction = _sheetHalf;
      ref.read(plannerProvider.notifier).toSearch();
    });
  }

  /// The back button (Android): first close whatever is open, only then leave
  /// the app. Not during navigation: leaving the app would stop navigation.
  void _back() {
    final planner = ref.read(plannerProvider);
    if (_menu != null || _incident != null) {
      setState(() {
        _menu = null;
        _incident = null;
      });
    } else if (ref.read(navigationProvider) != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).stopFirst)),
        );
    } else if (planner.routeMode) {
      _sheetFraction = _sheetHalf;
      ref.read(plannerProvider.notifier).toSearch();
    } else if (planner.found != null) {
      ref.read(plannerProvider.notifier).closePlace();
    }
  }

  /// The sheet's handle. The sheet itself only moves along with its list; the
  /// handle is outside it, so dragging is done by hand here. A tap toggles
  /// between half and full.
  Widget _handle(double height) {
    final positions = [0.0, _sheetLow(height), _sheetHalf, _sheetFull];
    void to(double target) => _sheet.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => to(_sheet.size < 0.6 ? _sheetFull : _sheetHalf),
      onVerticalDragUpdate: (details) => _sheet.jumpTo(
        (_sheet.size - details.primaryDelta! / height).clamp(
          positions.first,
          positions.last,
        ),
      ),
      onVerticalDragEnd: (details) {
        // A firm swipe goes on to the next position; otherwise the nearest
        // one.
        final speed = -(details.primaryVelocity ?? 0) / height;
        final now = _sheet.size;
        final target = speed.abs() > 0.8
            ? (speed > 0
                  ? positions.firstWhere(
                      (l) => l > now + 0.01,
                      orElse: () => positions.last,
                    )
                  : positions.lastWhere(
                      (l) => l < now - 0.01,
                      orElse: () => positions.first,
                    ))
            : positions.reduce(
                (a, b) => (a - now).abs() < (b - now).abs() ? a : b,
              );
        to(target);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: SizedBox(
          height: 22,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The instruction on top, arrival and stop below; the map in between stays
  /// clear. Each block its own interceptor: one over the whole screen would make
  /// the map unusable on the web.
  Widget _navigationOverlay(NavigationState nav, bool wide) {
    final l = AppLocalizations.of(context);
    final actions = ref.read(navigationProvider.notifier);
    Widget block(Widget child) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: PointerInterceptor(child: child),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: wide
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.stretch,
          children: [
            block(
              NavigationHeader(
                nav,
                onTap: nav.status == null || nav.arrived
                    ? null
                    : () => _showSteps(nav),
              ),
            ),
            const Spacer(),
            // Bottom left: speed (car), and "Resume" when you're looking
            // around yourself.
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (ref.watch(settingsProvider).profile == Profile.car &&
                      !nav.arrived)
                    PointerInterceptor(
                      child: SpeedLimitSign(
                        limit: nav.limit,
                        source: nav.limitSource,
                        speed: nav.fix?.speed,
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (!_following && !nav.arrived)
                    PointerInterceptor(
                      child: FloatingActionButton.extended(
                        onPressed: () {
                          _resume?.cancel();
                          setState(() => _following = true);
                        },
                        icon: const Icon(Icons.navigation),
                        label: Text(l.resume),
                      ),
                    ),
                ],
              ),
            ),
            if (nav.suggestion case final suggestion?) ...[
              block(
                SuggestionCard(
                  suggestion,
                  onAccept: actions.acceptSuggestion,
                  onIgnore: actions.ignoreSuggestion,
                ),
              ),
              const SizedBox(height: 8),
            ],
            block(
              NavigationFooter(
                nav,
                onStop: () {
                  // After arrival the route is done: back to an empty screen.
                  // Stopping earlier keeps the route so you can resume it.
                  if (nav.arrived) {
                    ref.read(plannerProvider.notifier).clear();
                  }
                  actions.stop();
                  _resume?.cancel();
                },
                onMute: actions.mute,
                onSearchAlong: () => _searchAlongRoute(nav),
                isSharing: _isSharing(),
                onShare: () => context.router.push(
                  SettingsCategoryRoute(
                    category: SettingsCategory.locationSharing.path,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// For the icon in the footer: null when location sharing is off, `true`
  /// when sending fails (the points then wait in the queue).
  bool? _isSharing() {
    if (!ref.watch(shareSettingsProvider).enabled) return null;
    return ref.watch(locationSharerProvider).error != null;
  }

  /// The arrow at the next turn, if it's close.
  List<LatLng>? _arrowFor(NavigationState? nav) {
    final status = nav?.status;
    if (nav == null ||
        status == null ||
        nav.arrived ||
        nav.recalculating ||
        status.toNext > _arrowWithin) {
      return null;
    }
    final old = _arrow;
    if (old != null &&
        identical(old.route, nav.route) &&
        old.index == status.next) {
      return old.line;
    }
    final line = turnArrow(nav.route, status.next);
    _arrow = (route: nav.route, index: status.next, line: line);
    return line;
  }

  /// During navigation: the rest of the directions, from the next
  /// maneuver.
  void _showSteps(NavigationState nav) {
    final status = nav.status;
    if (status == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PointerInterceptor(
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppLocalizations.of(context).instructions,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  StepList(
                    nav.route,
                    startIndex: status.next,
                    toNext: status.toNext,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// During navigation: search for a stop along the rest of the route.
  Future<void> _searchAlongRoute(NavigationState nav) async {
    final status = nav.status;
    final line = status == null
        ? nav.route.points
        : [status.onRoute, ...nav.route.points.skip(status.segment + 1)];
    final chosen = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      builder: (context) => PointerInterceptor(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SingleChildScrollView(
              child: AlongRouteSearch(
                line: line,
                onChosen: (place) => Navigator.of(context).pop(place),
              ),
            ),
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    ref.read(navigationProvider.notifier).addStop(chosen);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).stopAdded(chosen.label)),
      ),
    );
  }

  /// What's going on at a tapped piece of traffic, next to where you tapped.
  /// Like the point menu: a plane over the map that closes on a tap.
  Widget _incidentOverlay(
    BuildContext context,
    Offset position,
    Map<String, dynamic> info,
  ) {
    final screen = MediaQuery.sizeOf(context);
    const width = 260.0, height = 140.0;
    return Positioned.fill(
      child: PointerInterceptor(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _incident = null),
          child: Stack(
            children: [
              Positioned(
                left: min(position.dx + 8, screen.width - width - 8),
                top: min(position.dy + 8, screen.height - height - 8),
                width: width,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(8),
                  child: TrafficIncident(info),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "As home" on the card of a found place, as long as there's no home yet. If
/// there is one, nothing -- changing it goes through the settings -- except on
/// the card of home itself: a check mark there.
class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.place,
    required this.current,
    required this.icon,
    required this.label,
    required this.savedLabel,
    required this.onSave,
  });

  final Place place;
  final Place? current;
  final IconData icon;
  final String label;
  final String savedLabel;
  final ValueChanged<Place?> onSave;

  @override
  Widget build(BuildContext context) {
    final existing = current;
    if (existing == null) {
      return TextButton.icon(
        onPressed: () => onSave(place),
        icon: Icon(icon),
        label: Text(label),
      );
    }
    if (meters(existing.point, place.point) >= 30) {
      return const SizedBox.shrink();
    }
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 18, color: color),
          const SizedBox(width: 4),
          Text(savedLabel, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    backgroundColor: Theme.of(context).colorScheme.surface,
    foregroundColor: Theme.of(context).colorScheme.onSurface,
    child: Icon(icon),
  );
}

/// Android without a configured server: there's nothing to show yet.
class _ServerRequired extends StatelessWidget {
  const _ServerRequired();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 48),
            const SizedBox(height: 12),
            Text(l.serverRequired),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.router.push(
                SettingsCategoryRoute(category: SettingsCategory.server.path),
              ),
              child: Text(l.settings),
            ),
          ],
        ),
      ),
    );
  }
}
