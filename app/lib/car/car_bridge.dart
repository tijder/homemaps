import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Brightness, Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../l10n/app_localizations.dart';
import '../map/map_images.dart';
import '../map/route_geojson.dart';
import '../models/place.dart';
import '../models/route.dart';
import '../navigation/navigation_provider.dart';
import '../navigation/route_geometry.dart';
import '../navigation/simulation.dart';
import '../providers/location.dart';
import '../providers/location_sharing.dart';
import '../providers/planner.dart';
import '../providers/saved_places.dart';
import '../providers/services.dart';
import '../providers/settings.dart';
import '../utils/formatting.dart';
import '../widgets/navigation_bar.dart' show CameraSign;
import 'car_api.g.dart';
import 'car_icons.dart';
import 'car_maneuvers.dart';

/// The channel to the car; tests override it with a fake.
final carHostProvider = Provider<CarHostApi>((_) => CarHostApi());

/// The bridge lives as long as the app: the car may connect at any moment.
final carBridgeProvider = Provider<CarBridge>((ref) {
  final bridge = CarBridge(ref, ref.watch(carHostProvider));
  ref.onDispose(bridge.dispose);
  bridge.init();
  return bridge;
});

/// What the car screen shows.
enum CarScreen { home, preview, navigating }

/// Between Dart and the car screens (Android Auto, CarPlay). Dart plans,
/// navigates and speaks as on the phone; this pushes what the car has to show
/// (the map's GeoJSON, the next maneuver, the ETA) and handles what the driver
/// does in the car. Everything the phone's screen does with the navigation
/// state, this does too, without widgets.
class CarBridge with WidgetsBindingObserver implements CarFlutterApi {
  CarBridge(this._ref, this._host);

  final Ref _ref;
  final CarHostApi _host;

  /// The car's screen; null while no car is connected.
  CarSurface? _surface;
  CarScreen _screen = CarScreen.home;
  bool _following = true;

  /// The images the car already has, by key.
  final _images = <String>{};
  final _arrows = TurnArrowCache();

  /// The last search, for [placeChosen] with `search:<n>`.
  List<Place> _searchResults = const [];

  // What was pushed last, so a fix only produces a call when something
  // visible changed.
  bool _navigating = false;
  RouteOption? _pushedRoute;
  RouteOption? _pushedSuggestion;
  int? _pushedSegment;
  List<LatLng>? _pushedArrow;
  String? _pushedManeuver;
  String? _pushedSpeed;
  bool? _pushedRecalculating;
  bool _arrivedShown = false;
  String? _alertShown;
  bool? _pushedMuted;
  String? _pushedStyle;

  CarSurface? get surface => _surface;
  CarScreen get screen => _screen;

  late AppLocalizations _l;
  late String _language;

  void init() {
    _locale(PlatformDispatcher.instance.locale);
    CarFlutterApi.setUp(this);
    WidgetsBinding.instance.addObserver(this);
    _send(_host.ready());
    _ref.listen(settingsProvider, (_, _) => _pushStyle());
    _ref.listen(locationProvider.select((s) => s.fix), (_, fix) {
      if (fix != null) _onFix(fix);
    });
    _ref.listen<NavigationState?>(navigationProvider, _onNavigation);
    _ref.listen(plannerProvider, (_, planner) {
      if (_screen == CarScreen.preview) _pushPreview(planner);
    });
    _ref.listen(savedPlacesProvider, (_, _) {
      if (_screen == CarScreen.home) _pushHome();
    });
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CarFlutterApi.setUp(null);
  }

  /// The phone went to dark mode or back: the map in the car follows, as
  /// the phone's map does.
  @override
  void didChangePlatformBrightness() => _pushStyle();

  /// The phone's language: nl is Dutch, everything else English (Valhalla
  /// knows 'nl-NL' and 'en-US').
  void _locale(Locale locale) {
    final dutch = locale.languageCode == 'nl';
    _l = lookupAppLocalizations(Locale(dutch ? 'nl' : 'en'));
    _language = dutch ? 'nl-NL' : 'en-US';
  }

  /// A call to the car; a failure (no native side, as on a test device
  /// without the car module) is logged, not thrown.
  Future<void> _send(Future<void> call) => call.catchError((Object error) {
    debugPrint('car: $error');
  });

  /// The labels of the templates.
  Map<String, String> get texts => {
    'whereTo': _l.carWhereTo,
    'home': _l.home,
    'work': _l.work,
    'recent': _l.recentPlaces,
    'favourites': _l.savedPlaces,
    'search': _l.searchPlace,
    'noResults': _l.carNoResults,
    'routes': _l.carRoutes,
    'calculating': _l.routeCalculating,
    'noRoute': _l.noRoute,
    'serverUnreachable': _l.serverUnreachable,
    'start': _l.startNavigation,
    'stop': _l.stopNavigation,
    'mute': _l.voiceOff,
    'unmute': _l.voiceOn,
    'recenter': _l.resume,
    'arrived': _l.arrived,
    'recalculating': _l.recalculatingBusy,
    'then': _l.afterwards,
    'toll': _l.withToll,
    'ferry': _l.withFerry,
    'delay': _l.delay,
    'accept': _l.accept,
    'ignore': _l.ignore,
    'fastest': _l.fastest,
    'noLocation': _l.navigatingWithoutLocation,
    'openApp': _l.carOpenApp,
    'searching': _l.locationSearching,
    'kmh': _l.kmh,
  };

  // ------------------------------------------------------------ from the car

  @override
  void connected(CarSurface surface) {
    _surface = surface;
    _images.clear();
    _pushedStyle = null;
    _send(_host.setTexts(texts));
    _pushStyle();
    unawaited(_pushMapImages());
    final nav = _ref.read(navigationProvider);
    if (nav != null) {
      // Plugged in mid-trip: everything from scratch.
      _navigating = false;
      _pushedRoute = null;
      _pushedSegment = null;
      _pushedArrow = null;
      _pushedManeuver = null;
      _pushedSpeed = null;
      _pushedRecalculating = null;
      _arrivedShown = false;
      _alertShown = null;
      _pushedMuted = null;
      _onNavigation(null, nav);
    } else if (_screen == CarScreen.preview) {
      _pushPreview(_ref.read(plannerProvider));
    } else {
      _screen = CarScreen.home;
      _pushHome();
    }
    final fix = _ref.read(locationProvider).fix;
    if (fix != null) _onFix(fix);
  }

  @override
  void disconnected() {
    _surface = null;
    _images.clear();
  }

  @override
  void surfaceChanged(CarSurface surface) {
    // The car's day or night mode changes nothing: the map follows the
    // phone, and the icons are white on our own blue panel.
    _surface = surface;
  }

  @override
  Future<void> placeChosen(String id) async {
    final place = _resolve(id);
    if (place == null) return;
    _screen = CarScreen.preview;
    _send(_host.showLoading(true));
    final fix = await _ref.read(locationProvider.notifier).turnOn();
    if (fix == null) {
      _screen = CarScreen.home;
      _send(_host.showMessage(_l.navigatingWithoutLocation, _l.carOpenApp));
      return;
    }
    final planner = _ref.read(plannerProvider.notifier);
    planner.language = _language;
    planner.toSearch();
    planner.showPlace(place);
    planner.startRoute();
    _pushPreview(_ref.read(plannerProvider));
  }

  Place? _resolve(String id) {
    final saved = _ref.read(savedPlacesProvider);
    final parts = id.split(':');
    return switch (parts.first) {
      'home' => saved.home,
      'work' => saved.work,
      'recent' => saved.recent.elementAtOrNull(int.parse(parts[1])),
      'search' => _searchResults.elementAtOrNull(int.parse(parts[1])),
      _ => null,
    };
  }

  @override
  Future<List<CarPlace>> search(String text) async {
    final photon = _ref.read(photonProvider);
    if (photon == null) return const [];
    final near = _ref.read(locationProvider).fix?.point;
    try {
      _searchResults = await photon.search(text, near: near);
    } on Object {
      _searchResults = const [];
    }
    return [
      for (final (i, place) in _searchResults.indexed)
        _carPlace('search:$i', place, 'search'),
    ];
  }

  CarPlace _carPlace(String id, Place place, String kind) => CarPlace(
    id: id,
    label: place.display(_l),
    detail: place.description,
    lat: place.point.latitude,
    lon: place.point.longitude,
    kind: kind,
  );

  @override
  void routeChosen(int index) {
    _ref.read(plannerProvider.notifier).choose(index);
  }

  @override
  Future<void> startTrip() async {
    final planner = _ref.read(plannerProvider);
    final route = planner.chosenRoute;
    final destinations = [
      for (final point in planner.points.skip(1)) ?point.place,
    ];
    if (route == null || destinations.isEmpty) return;
    if (_ref.read(locationProvider).fix == null) {
      _send(_host.showMessage(_l.navigatingWithoutLocation, _l.carOpenApp));
      return;
    }
    _following = true;
    _ref.read(savedPlacesProvider.notifier).remember(destinations.last);
    await _ref
        .read(navigationProvider.notifier)
        .start(
          route: route,
          destinations: destinations,
          texts: NavTexts.of(
            _l,
            _language,
            destinations.last.display(_l),
            sharing: _ref.read(shareSettingsProvider).enabled,
          ),
        );
  }

  @override
  void stopTrip() {
    _ref.read(navigationProvider.notifier).stop();
    _ref.read(plannerProvider.notifier).clear();
  }

  @override
  void toggleMute() {
    final nav = _ref.read(navigationProvider);
    if (nav != null) _ref.read(navigationProvider.notifier).mute(!nav.muted);
  }

  @override
  void userMovedMap() {
    _following = false;
    _send(_host.setFollowing(false));
  }

  @override
  void recenter() {
    _following = true;
    _send(_host.setFollowing(true));
    final fix = _ref.read(locationProvider).fix;
    if (fix != null) _onFix(fix);
  }

  @override
  void alertAnswered(String id, bool accepted) {
    if (id != 'faster') return;
    final notifier = _ref.read(navigationProvider.notifier);
    if (accepted) {
      notifier.acceptSuggestion();
    } else {
      notifier.ignoreSuggestion();
    }
  }

  @override
  void autoDriveEnabled() {
    final nav = _ref.read(navigationProvider);
    final fix = _ref.read(locationProvider).fix;
    final start = fix?.point ?? nav?.route.points.firstOrNull;
    if (start == null) return;
    final simulation = SimulationSource(start);
    _ref.read(locationSourceProvider.notifier).use(simulation);
    if (nav != null) simulation.drive(nav.route);
  }

  @override
  Future<void> navigateTo(
    double? lat,
    double? lon,
    String? label,
    String? query,
  ) async {
    if (_ref.read(navigationProvider) != null) return;
    Place? place;
    if (lat != null && lon != null) {
      final point = LatLng(lat, lon);
      place = label == null || label.isEmpty
          ? Place.fromPoint(point)
          : Place(label: label, point: point);
    } else if (query != null && query.isNotEmpty) {
      await search(query);
      place = _searchResults.firstOrNull;
      if (place == null) {
        _send(_host.showMessage(_l.notFound(query), ''));
        return;
      }
    }
    if (place == null) return;
    _searchResults = [place];
    await placeChosen('search:0');
  }

  @override
  void backToHome() {
    if (_ref.read(navigationProvider) != null) return;
    _ref.read(plannerProvider.notifier).clear();
    _screen = CarScreen.home;
    _pushHome();
  }

  // -------------------------------------------------------------- to the car

  Future<void> _pushMapImages() async {
    await _image('arrow-head', () => arrowHeadPng(), 2);
    await _image('puck', () => locationPuckPng(), 2);
  }

  /// Registers the image once per connection.
  Future<void> _image(
    String key,
    Future<Uint8List> Function() draw,
    double scale,
  ) async {
    if (_surface == null || !_images.add(key)) return;
    await _send(_host.registerImage(key, await draw(), scale));
  }

  /// The map style, as on the phone: the night version of the regular map
  /// when the phone is in dark mode (or the theme says night). The car's
  /// own day or night mode doesn't count, as the phone's map doesn't look
  /// at the car either (see `map_screen.dart`).
  void _pushStyle() {
    if (_surface == null) return;
    final config = _ref.read(appConfigProvider);
    if (config == null) return;
    final settings = _ref.read(settingsProvider);
    final url = config.styleUrl(settings.style);
    final night =
        settings.style == MapStyle.map.id &&
        switch (settings.theme) {
          MapTheme.automatic =>
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark,
          MapTheme.day => false,
          MapTheme.night => true,
        };
    final wanted = night ? 'night:$url' : url;
    if (wanted == _pushedStyle) return;
    _pushedStyle = wanted;
    if (!night) {
      _send(_host.setStyle(url, false, false));
      return;
    }
    // Until the night style is there (or if it fails) the regular one.
    _send(_host.setStyle(url, false, true));
    _ref
        .read(nightStyleProvider(url).future)
        .then((json) {
          if (_pushedStyle == wanted && _surface != null) {
            _send(_host.setStyle(json, true, true));
          }
        })
        .catchError((Object _) {});
  }

  void _pushHome() {
    if (_surface == null) return;
    final saved = _ref.read(savedPlacesProvider);
    final location = _ref.read(locationProvider);
    _send(
      _host.showHome(
        [
          if (saved.home case final home?) _carPlace('home', home, 'home'),
          if (saved.work case final work?) _carPlace('work', work, 'work'),
        ],
        [
          for (final (i, place) in saved.recent.indexed)
            _carPlace('recent:$i', place, 'recent'),
        ],
        location.fix != null || location.status == LocationStatus.searching,
      ),
    );
    _send(_host.setRoutes(jsonEncode(emptyFeatureCollection)));
    _send(_host.setDriven(jsonEncode(emptyFeatureCollection)));
    _send(_host.setArrow(jsonEncode(emptyFeatureCollection)));
  }

  void _pushPreview(PlannerState planner) {
    if (_surface == null) return;
    final destination = planner.points.last.place;
    if (destination == null) return;
    final label = destination.display(_l);
    switch (planner.routes) {
      case AsyncLoading():
        _send(_host.showLoading(true));
      case AsyncError(:final error):
        _send(_host.showLoading(false));
        _send(_host.showMessage(_l.noRoute, '$error'));
      case AsyncData(:final value):
        _send(_host.showLoading(false));
        if (value.isEmpty) return;
        _send(
          _host.setRoutes(
            jsonEncode(routesFeatureCollection(value, planner.chosen)),
          ),
        );
        _send(
          _host.showRoutePreview(label, [
            for (final (i, route) in value.indexed)
              CarRouteSummary(
                index: i,
                via: mainRoads(route).join(', '),
                meters: route.meters,
                seconds: route.seconds,
                delaySeconds: route.delay,
                hasToll: route.hasToll,
                hasFerry: route.hasFerry,
              ),
          ], planner.chosen),
        );
        _fit(value[planner.chosen.clamp(0, value.length - 1)].points);
    }
  }

  void _fit(List<LatLng> points) {
    if (points.isEmpty) return;
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    for (final p in points) {
      if (p.latitude < south) south = p.latitude;
      if (p.latitude > north) north = p.latitude;
      if (p.longitude < west) west = p.longitude;
      if (p.longitude > east) east = p.longitude;
    }
    _send(
      _host.fitBounds(
        CarBounds(south: south, west: west, north: north, east: east),
        48 * (_surface?.density ?? 1),
      ),
    );
  }

  void _onFix(LocationFix fix) {
    if (_surface == null) return;
    final nav = _ref.read(navigationProvider);
    final onRoad = snapToRoute(nav, fix) ?? fix;
    _send(
      _host.setPosition(
        CarPosition(
          lat: onRoad.point.latitude,
          lon: onRoad.point.longitude,
          heading: onRoad.heading,
          speed: onRoad.speed,
          accuracy: onRoad.accuracy,
        ),
      ),
    );
    if (!_following) return;
    final navigating = nav != null && !nav.arrived;
    _send(
      _host.followCamera(
        navigating
            ? CarCamera(
                lat: onRoad.point.latitude,
                lon: onRoad.point.longitude,
                zoom: followZoom(onRoad.speed ?? 0) + carZoomOffset,
                bearing: onRoad.heading ?? nav.status?.routeHeading ?? 0,
                tilt: followTilt,
                // About the time until the next fix, so the map glides.
                animateMs: 1000,
              )
            : CarCamera(
                lat: onRoad.point.latitude,
                lon: onRoad.point.longitude,
                zoom: 15 + carZoomOffset,
                bearing: 0,
                tilt: 0,
                animateMs: 500,
              ),
      ),
    );
  }

  void _onNavigation(NavigationState? _, NavigationState? nav) {
    if (nav == null) {
      if (_navigating) {
        _navigating = false;
        _pushedRoute = null;
        _pushedSuggestion = null;
        _pushedSegment = null;
        _pushedArrow = null;
        _pushedManeuver = null;
        _pushedSpeed = null;
        _pushedRecalculating = null;
        _arrivedShown = false;
        _alertShown = null;
        _pushedMuted = null;
        _send(_host.endNavigation());
        _screen = CarScreen.home;
        _pushHome();
      }
      return;
    }
    if (_surface == null) return;
    if (!_navigating) {
      _navigating = true;
      _screen = CarScreen.navigating;
      _following = true;
      _send(_host.setFollowing(true));
      _send(_host.startNavigation(_trip(nav)));
    }
    if (!identical(_pushedRoute, nav.route) ||
        !identical(_pushedSuggestion, nav.suggestion?.route)) {
      _pushedRoute = nav.route;
      _pushedSuggestion = nav.suggestion?.route;
      _send(
        _host.setRoutes(
          jsonEncode(
            routesFeatureCollection([nav.route, ?nav.suggestion?.route], 0),
          ),
        ),
      );
    }
    final segment = nav.status?.segment;
    if (segment != _pushedSegment) {
      _pushedSegment = segment;
      _send(
        _host.setDriven(jsonEncode(lineFeatureCollection(drivenLine(nav)))),
      );
    }
    final arrow = _arrows.arrowFor(nav);
    if (!identical(arrow, _pushedArrow)) {
      _pushedArrow = arrow;
      _send(_host.setArrow(jsonEncode(arrowFeatureCollection(arrow))));
    }
    if (nav.recalculating != _pushedRecalculating) {
      _pushedRecalculating = nav.recalculating;
      _send(_host.setRecalculating(nav.recalculating));
    }
    if (nav.muted != _pushedMuted) {
      _pushedMuted = nav.muted;
      _send(_host.setMuted(nav.muted));
    }
    final suggestion = nav.suggestion;
    final alertId = suggestion == null ? null : 'faster';
    if (alertId != _alertShown) {
      if (_alertShown != null) _send(_host.dismissAlert(_alertShown!));
      _alertShown = alertId;
      if (suggestion != null) {
        final minutes = (suggestion.secondsFaster / 60).round();
        final via = suggestion.via;
        _send(
          _host.showAlert(
            CarAlert(
              id: 'faster',
              title: _l.suggestionFaster(minutes),
              text: via == null ? '' : _l.suggestionVia(via),
              accept: _l.accept,
              reject: _l.ignore,
              seconds: NavigationNotifier.suggestionDuration.inSeconds,
            ),
          ),
        );
      }
    }
    if (nav.arrived) {
      if (!_arrivedShown) {
        _arrivedShown = true;
        _send(
          _host.showArrived(nav.destinations.lastOrNull?.display(_l) ?? ''),
        );
      }
      return;
    }
    unawaited(_pushManeuver(nav));
    unawaited(_pushSpeed(nav));
  }

  CarTrip _trip(NavigationState nav) {
    final status = nav.status;
    final remainingSeconds = status?.remainingSeconds ?? nav.route.seconds;
    return CarTrip(
      destinationLabel: nav.destinations.lastOrNull?.display(_l) ?? '',
      remainingMeters: status?.remainingMeters ?? nav.route.meters,
      remainingSeconds: remainingSeconds,
      etaEpochMs:
          DateTime.now().millisecondsSinceEpoch +
          (remainingSeconds * 1000).round(),
    );
  }

  /// The next maneuver, only when something visible changed: the maneuver,
  /// its rounded distance, the lanes or the ETA minute.
  Future<void> _pushManeuver(NavigationState nav) async {
    final status = nav.status;
    if (status == null || nav.recalculating || _surface == null) return;
    final maneuvers = nav.route.maneuvers;
    final next = maneuvers[status.next];
    final toNext = roundDistance(status.toNext);
    final lanes = nav.lanes;
    final laneAhead = lanes == null || lanes.atManeuver
        ? null
        : distance(roundDistance(lanes.ahead), _l.localeName);
    final laneKey = lanes == null
        ? null
        : lanesIconKey(lanes.perLane, ahead: laneAhead);
    final sign = next.signpost;
    final signKey = sign == null ? null : signIconKey(sign);
    final etaMinute = (status.remainingSeconds / 60).round();
    final signature =
        '${identityHashCode(nav.route)}:${status.next}:$toNext:$laneKey:'
        '$etaMinute';
    if (signature == _pushedManeuver) return;
    _pushedManeuver = signature;

    final iconKey = maneuverIconKey(next);
    await _image(iconKey, () => maneuverPng(next), 4);
    CarManeuver? then;
    if (afterwardsIndex(nav.route, status.next) case final i?) {
      final after = maneuvers[i];
      final afterKey = maneuverIconKey(after);
      await _image(afterKey, () => maneuverPng(after), 4);
      then = carManeuver(
        after,
        _l,
        iconKey: afterKey,
        metersToNext: next.meters,
      );
    }
    if (lanes != null) {
      await _image(
        laneKey!,
        () => lanesPng(lanes.perLane, ahead: laneAhead),
        3,
      );
    }
    if (sign != null) {
      final exit = sign.exit;
      await _image(
        signKey!,
        () => signPng(sign, exitText: exit == null ? null : _l.exit(exit)),
        3,
      );
    }
    // Another maneuver came along while the icons were drawn.
    if (_pushedManeuver != signature || _surface == null) return;
    await _send(
      _host.updateManeuver(
        carManeuver(
          next,
          _l,
          iconKey: iconKey,
          metersToNext: toNext,
          signIconKey: signKey,
          then: [?then],
          lanes: lanes?.perLane,
          lanesIconKey: laneKey,
          lanesAhead: lanes == null || lanes.atManeuver ? null : lanes.ahead,
        ),
        _trip(nav),
      ),
    );
  }

  /// Your speed, the limit, the camera ahead and the matrix signs: on every
  /// fix on which one of them changed.
  Future<void> _pushSpeed(NavigationState nav) async {
    if (_surface == null) return;
    final speedMs = nav.fix?.speed;
    final kmh = speedMs == null ? null : (speedMs * 3.6).round();
    final camera = CameraSign.describe(_l, nav.camera, nav.section);
    final cameraKey = camera == null ? null : 'camera-${camera.kind.name}';
    final matrix = nav.matrix?.perLane;
    final matrixKey = matrix == null ? null : matrixIconKey(matrix);
    final signature =
        '$kmh:${nav.limit}:${nav.limitSource}:$cameraKey:${camera?.text}:'
        '${camera?.detail}:${camera?.over}:$matrixKey';
    if (signature == _pushedSpeed) return;
    _pushedSpeed = signature;
    if (camera != null) {
      await _image(
        cameraKey!,
        () => cameraPng(CameraSign.icon(camera.kind)),
        2,
      );
    }
    if (matrix != null) {
      await _image(matrixKey!, () => matrixPng(matrix), 3);
    }
    if (_pushedSpeed != signature || _surface == null) return;
    await _send(
      _host.setSpeed(
        CarSpeed(
          limitKmh: nav.limit,
          limitSource: nav.limitSource.name,
          speedMs: speedMs,
          cameraIconKey: cameraKey,
          cameraText: camera?.text,
          cameraDetail: camera?.detail,
          cameraOver: camera?.over ?? false,
          matrixIconKey: matrixKey,
        ),
      ),
    );
  }
}
