import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/app_localizations.dart';
import '../models/place.dart';
import '../models/profile.dart';
import '../models/route.dart';
import '../providers/services.dart';
import '../providers/settings.dart';
import '../providers/location.dart';
import '../services/valhalla_service.dart';
import '../utils/msi.dart';
import '../utils/timed_speed_limits.dart';
import '../utils/temporary_speed_limits.dart';
import 'announcer.dart';
import 'lane_choice.dart';
import 'simulation.dart';
import 'voice.dart';
import 'route_tracker.dart';

/// What navigation says and shows in the user's language. The screen builds
/// this from the translations; the notifier has no context of its own.
class NavTexts {
  const NavTexts({
    required this.language,
    required this.notificationHeading,
    required this.notificationBody,
    required this.recalculating,
    required this.fasterRoute,
    required this.withDistance,
    required this.warning,
  });

  /// For the voice, for example 'nl-NL'.
  final String language;

  /// The persistent notification on Android while navigation is running.
  final String notificationHeading;
  final String notificationBody;
  final String recalculating;
  final String Function(int minutesFaster) fasterRoute;
  final String Function(double meters, String sentence) withDistance;

  /// "Caution: accident in 2 kilometers." for an incident on the route.
  final String Function(String kind, double meters) warning;

  /// [language] as Valhalla knows it ('nl-NL', 'en-US'). With [sharing] the
  /// notification says the location is sent to your own server.
  factory NavTexts.of(
    AppLocalizations l,
    String language,
    String destination, {
    bool sharing = false,
  }) {
    final numberFormat = NumberFormat('#0.#', language.replaceAll('-', '_'));
    String spoken(double meters) => meters < 1000
        // To 50 m: "in 437 meters" sounds like a measurement error.
        ? l.spokenMeters(max(50, (meters / 50).round() * 50))
        : l.spokenKilometers(numberFormat.format(meters / 1000));
    return NavTexts(
      language: language,
      notificationHeading: l.navigationNotificationTitle(destination),
      notificationBody: sharing
          ? l.navigationNotificationSharing
          : l.navigationNotificationText,
      recalculating: l.recalculating,
      fasterRoute: l.fasterRoute,
      warning: (kind, meters) => l.warningOnRoute(
        switch (kind) {
          'accident' => l.incidentAccident,
          'breakdown' => l.incidentBreakdown,
          'bridge' => l.incidentBridge,
          _ => l.incidentObstacle,
        }.toLowerCase(),
        spoken(meters),
      ),
      withDistance: (meters, sentence) => l.inDistance(
        spoken(meters),
        // "In 400 meters turn left", not "... Turn left".
        sentence.isEmpty
            ? sentence
            : sentence[0].toLowerCase() + sentence.substring(1),
      ),
    );
  }
}

/// A faster route that traffic produced en route; the user decides.
class Suggestion {
  const Suggestion(this.route, this.secondsFaster, this.expires);

  final RouteOption route;
  final double secondsFaster;

  /// Without a choice it expires then, and the current route stays.
  final DateTime expires;

  /// The road that makes the difference: the longest maneuver with a name, for
  /// "via N303" (the road number if it has one).
  String? get via {
    Maneuver? longest;
    for (final m in route.maneuvers) {
      if (m.streets.isNotEmpty &&
          (longest == null || m.meters > longest.meters)) {
        longest = m;
      }
    }
    final streets = longest?.streets;
    return streets == null ? null : mainRoadNumber(streets) ?? streets.first;
  }
}

class NavigationState {
  const NavigationState({
    required this.route,
    required this.destinations,
    this.status,
    this.fix,
    this.muted = false,
    this.recalculating = false,
    this.arrived = false,
    this.suggestion,
    this.limit,
    this.limitSource = LimitSource.osm,
    this.lanes,
    this.matrix,
  });

  final RouteOption route;

  /// What's still ahead: the waypoints and the destination.
  final List<Place> destinations;
  final NavStatus? status;
  final LocationFix? fix;
  final bool muted;
  final bool recalculating;
  final bool arrived;
  final Suggestion? suggestion;

  /// The speed limit here (km/h), or null if unknown.
  final int? limit;

  /// Where [limit] comes from.
  final LimitSource limitSource;

  /// The lanes that belong in the header (see [chooseLanes]), and how far away
  /// that intersection is. Null if there's nothing to choose (yet).
  final LaneChoice? lanes;

  /// The MSI signs on the next gantry that shows something, per lane from left
  /// to right (see [Gantry]), and how far away it is.
  final ({double ahead, List<String> perLane})? matrix;

  NavigationState copyWith({
    RouteOption? route,
    List<Place>? destinations,
    NavStatus? status,
    LocationFix? fix,
    bool? muted,
    bool? recalculating,
    bool? arrived,
    Suggestion? Function()? suggestion,
    int? Function()? limit,
    LimitSource? limitSource,
    LaneChoice? Function()? lanes,
    ({double ahead, List<String> perLane})? Function()? matrix,
  }) => NavigationState(
    route: route ?? this.route,
    destinations: destinations ?? this.destinations,
    status: status ?? this.status,
    fix: fix ?? this.fix,
    muted: muted ?? this.muted,
    recalculating: recalculating ?? this.recalculating,
    arrived: arrived ?? this.arrived,
    suggestion: suggestion != null ? suggestion() : this.suggestion,
    limit: limit != null ? limit() : this.limit,
    limitSource: limitSource ?? this.limitSource,
    lanes: lanes != null ? lanes() : this.lanes,
    matrix: matrix != null ? matrix() : this.matrix,
  );
}

/// Where the speed limit en route comes from.
enum LimitSource {
  /// The fixed limit from OSM.
  osm,

  /// A limit that depends on the time of day (130 after 19:00).
  timeOfDay,

  /// A temporary limit for roadworks or an event (NDW).
  roadworks,

  /// The MSI signs above the road (red ring).
  msi,
}

/// Null while not navigating.
class NavigationNotifier extends Notifier<NavigationState?> {
  RouteTracker? _tracker;
  Announcer? _announcer;
  ProviderSubscription<LocationFix?>? _fixes;
  Timer? _fasterTimer;
  CancelToken? _inFlight;
  DateTime _lastRecalculation = DateTime(0);

  Timer? _suggestionExpiry;

  /// Incidents (accident, breakdown, object) on the current route, in order of
  /// where they are; and which have already been announced.
  List<({String id, double along, String kind})> _incidents = const [];
  final _warned = <String>{};
  ProviderSubscription<Map<String, dynamic>?>? _layerSubscription;

  /// Speed limit and OSM way per stretch of the current route (see
  /// [ValhallaService.speedLimits]); empty until they're in.
  List<StretchLimit> _limits = const [];

  /// The gantries with MSI signs above the route, from the traffic layer.
  List<Gantry> _gantries = const [];

  /// Temporary speed limit per stretch of the route (roadworks, event), from
  /// the traffic layer; see [temporarySpeedLimits].
  List<int?> _temporary = const [];

  /// The intersections with lanes on the current route, in order along the
  /// route (see [ValhallaService.lanes]); empty until they're in.
  List<({double along, List<Lane> perLane})> _lanes = const [];

  /// Rejected routes (by length), so as not to keep suggesting the same one.
  final _rejected = <int>{};

  /// How long a suggestion stays up without a choice.
  static const suggestionDuration = Duration(seconds: 45);

  /// Waypoints on the current route already passed (and removed from the
  /// destinations).
  int _viasPassed = 0;
  late NavTexts _texts;
  late Profile _profile;

  /// A recalculation en route at most this often: in a place without a route
  /// (a car park) it would otherwise happen every second.
  static const _pauseBetweenRecalculations = Duration(seconds: 10);

  /// Further than this from the route at the start: recalculate right away.
  static const _farFromStart = 150.0;

  /// For the car: check this often whether traffic makes a faster route
  /// available (the importer refreshes traffic just as often).
  static const trafficInterval = Duration(minutes: 5);

  /// Captured at the start: ref may no longer be used during cleanup.
  Voice? _voiceAtStart;
  bool _active = false;

  @override
  NavigationState? build() {
    ref.onDispose(() => _cleanUp(provider: false));
    return null;
  }

  Voice get _voice => _voiceAtStart ?? ref.read(voiceProvider);

  Future<void> start({
    required RouteOption route,
    required List<Place> destinations,
    required NavTexts texts,
  }) async {
    _cleanUp();
    _rejected.clear();
    _active = true;
    _voiceAtStart = ref.read(voiceProvider);
    _texts = texts;
    _profile = ref.read(settingsProvider).profile;
    _newRoute(route, destinations);
    await WakelockPlus.enable().catchError((Object _) {});
    await _voice.begin(texts.language).catchError((Object _) {});
    ref.read(locationProvider.notifier).navigation((
      title: texts.notificationHeading,
      text: texts.notificationBody,
    ));
    // New traffic data (every minute en route): check again what's on the
    // route. Also when the layer is off on the map.
    ref.read(enRouteProvider.notifier).apply(true);
    _layerSubscription = ref.listen(
      trafficLayerProvider.select((v) => v.value),
      (_, layer) {
        if (state case final now?) _readLayer(now.route, layer);
      },
      fireImmediately: true,
    );
    // Speed limits by time of day: fetch once, then from memory.
    ref.read(timedSpeedLimitsProvider);
    _fixes = ref.listen(locationProvider.select((t) => t.fix), (_, fix) {
      if (fix != null) _onFix(fix);
    }, fireImmediately: true);
    if (_profile == Profile.car && ref.read(settingsProvider).liveTraffic) {
      _fasterTimer = Timer.periodic(trafficInterval, (_) => searchFaster());
    }
  }

  void stop() {
    _cleanUp();
    state = null;
  }

  void mute(bool muted) {
    if (muted) _voice.stop();
    state = state?.copyWith(muted: muted);
  }

  /// [provider]: also return the location stream to normal. Not when disposing
  /// the provider itself; ref can't be used then.
  void _cleanUp({bool provider = true}) {
    _fixes?.close();
    _fixes = null;
    _layerSubscription?.close();
    _layerSubscription = null;
    _fasterTimer?.cancel();
    _fasterTimer = null;
    _suggestionExpiry?.cancel();
    _suggestionExpiry = null;
    _inFlight?.cancel();
    if (!_active) return;
    _active = false;
    WakelockPlus.disable().catchError((Object _) {});
    _voiceAtStart?.stop().catchError((Object _) {});
    if (provider) {
      ref.read(locationProvider.notifier).navigation(null);
      ref.read(enRouteProvider.notifier).apply(false);
    }
  }

  void _newRoute(RouteOption route, List<Place> destinations) {
    _viasPassed = 0;
    _limits = const [];
    _temporary = const [];
    _gantries = const [];
    _fetchLimits(route);
    _lanes = const [];
    _fetchLanes(route);
    _incidents = const [];
    _tracker = RouteTracker(route);
    _announcer = Announcer(route, _profile, withDistance: _texts.withDistance);
    final source = ref.read(locationSourceProvider);
    if (source is SimulationSource) source.drive(route);
    state = NavigationState(
      route: route,
      destinations: destinations,
      fix: state?.fix,
      muted: state?.muted ?? false,
    );
    _readLayer(route, ref.read(trafficLayerProvider).value);
  }

  /// What in the traffic layer matters for the route: incidents, temporary
  /// speed limits and MSI signs.
  void _readLayer(RouteOption route, Map<String, dynamic>? layer) {
    _readIncidents(route, layer);
    _temporary = temporarySpeedLimits(route.points, layer);
    final tracker = _tracker;
    if (tracker != null && identical(tracker.route, route)) {
      _gantries = gantriesOnRoute(tracker, layer);
    }
  }

  /// Which incidents from the traffic layer are on this route: within 30 m of
  /// the line, and on your side of the road (an accident on the other
  /// carriageway of the motorway is close by too). An open bridge has no
  /// side.
  void _readIncidents(RouteOption route, Map<String, dynamic>? layer) {
    final tracker = _tracker;
    if (layer == null || tracker == null || !identical(tracker.route, route)) {
      return;
    }
    final found = <({String id, double along, String kind})>[];
    for (final feature in (layer['features'] as List? ?? const [])) {
      if (feature is! Map) continue;
      final props = (feature['properties'] as Map?) ?? const {};
      final kind = props['kind'];
      final geometry = feature['geometry'] as Map?;
      if (kind is! String ||
          !const {
            'accident',
            'breakdown',
            'obstacle',
            'bridge',
          }.contains(kind) ||
          geometry?['type'] != 'Point') {
        continue;
      }
      final c = (geometry!['coordinates'] as List).cast<num>();
      final position = tracker.locate(LatLng(c[1].toDouble(), c[0].toDouble()));
      final heading = props['bearing'];
      if (position.distance > 30) continue;
      if (heading is num &&
          angleDiff(heading.toDouble(), position.heading) > 90) {
        continue;
      }
      found.add((
        id: '${feature['id']}:$kind:${c[0]},${c[1]}',
        along: position.along,
        kind: kind,
      ));
    }
    found.sort((a, b) => a.along.compareTo(b.along));
    _incidents = found;
  }

  /// How far ahead an incident on the route is announced.
  double get _warnDistance => switch (_profile) {
    Profile.car => 2000,
    Profile.bike => 500,
    Profile.walk => 200,
  };

  /// The speed limit here. The MSI signs above the road take precedence (red
  /// ring); otherwise the lower of a temporary one (roadworks) and the normal
  /// one, where the normal one may depend on the time of day (130 after
  /// 19:00).
  ({int? kmh, LimitSource source}) _limit(NavStatus status) {
    if (msiLimit(_gantries, status.along) case final msi?) {
      return (kmh: msi, source: LimitSource.msi);
    }
    final segment = status.segment;
    final stretch = segment < _limits.length
        ? _limits[segment]
        : (limit: null, way: null);
    final times =
        ref.read(timedSpeedLimitsProvider).value ?? TimedSpeedLimits.empty;
    final now = times.limitAt(stretch.way, stretch.limit, DateTime.now());
    final normal = (
      kmh: now,
      source: now != stretch.limit ? LimitSource.timeOfDay : LimitSource.osm,
    );
    final work = segment < _temporary.length ? _temporary[segment] : null;
    if (work != null && (normal.kmh == null || work < normal.kmh!)) {
      return (kmh: work, source: LimitSource.roadworks);
    }
    return normal;
  }

  /// In the background: the speed limits along the route (car only).
  Future<void> _fetchLimits(RouteOption route) async {
    final valhalla = ref.read(valhallaProvider);
    if (valhalla == null || _profile != Profile.car) return;
    final limits = await valhalla
        .speedLimits(route.points, _profile)
        .catchError((Object _) => null);
    // A different route in the meantime: this one no longer applies.
    if (limits != null && identical(state?.route, route)) {
      _limits = limits;
    }
  }

  /// In the background: the lanes along the route (car only).
  Future<void> _fetchLanes(RouteOption route) async {
    final valhalla = ref.read(valhallaProvider);
    if (valhalla == null || _profile != Profile.car) return;
    final advice = await valhalla
        .lanes(route.points, _profile)
        .catchError((Object _) => null);
    final tracker = _tracker;
    if (advice == null ||
        tracker == null ||
        !identical(state?.route, route) ||
        !identical(tracker.route, route)) {
      return;
    }
    final along = tracker.alongOf([for (final a in advice) a.position]);
    _lanes = [
      for (final (i, a) in advice.indexed)
        if (along[i] != null) (along: along[i]!, perLane: a.perLane),
    ];
  }

  void _onFix(LocationFix fix) {
    final now = state, tracker = _tracker, announcer = _announcer;
    if (now == null || tracker == null || announcer == null || now.arrived) {
      return;
    }
    final status = tracker.track(fix);
    // The first fix is far from the start ("from" was another address): don't
    // read out that route first, get a new one from here right away.
    if (now.status == null &&
        status.deviation > _farFromStart &&
        DateTime.now().difference(_lastRecalculation) >
            _pauseBetweenRecalculations) {
      state = now.copyWith(status: status, fix: fix);
      _recalculate(fix);
      return;
    }
    if (!now.muted) {
      for (final sentence in announcer.at(status, fix.speed ?? 0)) {
        _voice.say(sentence);
      }
      // An accident or breakdown ahead of you on the route: once.
      for (final incident in _incidents) {
        final ahead = incident.along - status.along;
        if (ahead < 0) continue;
        if (ahead > _warnDistance) break;
        if (_warned.add(incident.id)) {
          _voice.say(_texts.warning(incident.kind, ahead));
        }
      }
    }
    // Past a waypoint: it no longer belongs in the next recalculation. The
    // destination itself always stays.
    final passed = [
      for (var i = 0; i < status.next; i++)
        if (now.route.maneuvers[i].isDestination) i,
    ].length;
    var destinations = now.destinations;
    if (passed > _viasPassed && destinations.length > 1) {
      final drop = (passed - _viasPassed).clamp(0, destinations.length - 1);
      destinations = destinations.sublist(drop);
      _viasPassed = passed;
    }
    final limit = _limit(status);
    state = now.copyWith(
      status: status,
      fix: fix,
      arrived: status.arrived,
      destinations: destinations,
      limit: () => limit.kmh,
      limitSource: limit.source,
      matrix: () => nextGantry(_gantries, status.along),
      lanes: () => chooseLanes(
        _lanes,
        along: status.along,
        maneuver: tracker.toManeuver(status.next),
        speed: fix.speed,
      ),
    );
    if (status.arrived) {
      // Done: no more screen-on and no background service. The screen keeps
      // showing "arrived" until you dismiss it.
      _fixes?.close();
      _fixes = null;
      _fasterTimer?.cancel();
      WakelockPlus.disable().catchError((Object _) {});
      ref.read(locationProvider.notifier).navigation(null);
      return;
    }
    if (status.offRoute &&
        !now.recalculating &&
        DateTime.now().difference(_lastRecalculation) >
            _pauseBetweenRecalculations) {
      if (!now.muted) _voice.say(_texts.recalculating);
      _recalculate(fix);
    }
  }

  /// Every few minutes, for the car: is there a clearly faster way from here
  /// now? Then a suggestion; only the user switches ([acceptSuggestion]).
  ///
  /// Both times are computed the same way -- the rest of the current route and
  /// the new one, both along their line with current traffic -- so a
  /// difference is really down to traffic and not to the calculation method.
  @visibleForTesting
  Future<void> searchFaster() async {
    final now = state;
    final valhalla = ref.read(valhallaProvider);
    final tracker = _tracker;
    final status = now?.status, fix = now?.fix;
    if (now == null ||
        valhalla == null ||
        tracker == null ||
        status == null ||
        fix == null ||
        now.recalculating ||
        now.arrived ||
        now.suggestion != null) {
      return;
    }
    final cancel = _inFlight = CancelToken();
    final settings = ref.read(settingsProvider);
    try {
      final routes = await valhalla.route(
        [fix.point, for (final target in now.destinations) target.point],
        _profile,
        language: _texts.language,
        liveTraffic: settings.liveTraffic,
        avoidMotorways: settings.avoidMotorways,
        avoidTolls: settings.avoidTolls,
        avoidFerries: settings.avoidFerries,
        alternatives: false,
        heading: fix.heading,
        cancel: cancel,
      );
      if (routes.isEmpty || cancel.isCancelled) return;
      final newValue = routes.first;
      if (_rejected.contains(_key(newValue))) return;
      final (currentTime, newTime) = await (
        valhalla.travelTime(
          tracker.rest(status),
          _profile,
          live: true,
          cancel: cancel,
        ),
        valhalla.travelTime(
          newValue.points,
          _profile,
          live: true,
          cancel: cancel,
        ),
      ).wait;
      final current = state;
      if (currentTime == null ||
          newTime == null ||
          current == null ||
          current.arrived ||
          cancel.isCancelled) {
        return;
      }
      final gain = currentTime - newTime;
      // Only for a real gain: two minutes, and at least a tenth.
      if (gain < 120 || gain < currentTime * 0.1) return;
      state = current.copyWith(
        suggestion: () =>
            Suggestion(newValue, gain, DateTime.now().add(suggestionDuration)),
      );
      if (!current.muted) {
        _voice.say(_texts.fasterRoute((gain / 60).round()));
      }
      _suggestionExpiry?.cancel();
      _suggestionExpiry = Timer(suggestionDuration, ignoreSuggestion);
    } on DioException {
      // No network: try again next time.
    } on RouteError {
      // No route from here: the current one stays.
    }
  }

  /// "Take": the suggested route from now on.
  void acceptSuggestion() {
    final now = state, suggestion = now?.suggestion;
    if (now == null || suggestion == null) return;
    _suggestionExpiry?.cancel();
    _newRoute(suggestion.route, now.destinations);
    if (state?.fix case final latest?) _onFix(latest);
  }

  /// A stop en route (fuel, groceries): before the rest of the destinations,
  /// and a new route from here right away.
  void addStop(Place stop) {
    final now = state, fix = now?.fix;
    if (now == null || fix == null || now.arrived) return;
    state = now.copyWith(destinations: [stop, ...now.destinations]);
    _recalculate(fix);
  }

  /// "Ignore", or nothing chosen for 45 seconds: the current route stays, and
  /// this one won't come up again.
  void ignoreSuggestion() {
    final now = state, suggestion = now?.suggestion;
    if (now == null || suggestion == null) return;
    _suggestionExpiry?.cancel();
    _rejected.add(_key(suggestion.route));
    state = now.copyWith(suggestion: () => null);
  }

  /// Two routes from (almost) the same place with the same length to 100 m are
  /// the same way for this purpose.
  static int _key(RouteOption route) => (route.meters / 100).round();

  Future<void> _recalculate(LocationFix fix) async {
    final now = state;
    final valhalla = ref.read(valhallaProvider);
    if (now == null || valhalla == null) return;
    _lastRecalculation = DateTime.now();
    final cancel = _inFlight = CancelToken();
    state = now.copyWith(recalculating: true);
    final settings = ref.read(settingsProvider);
    try {
      final routes = await valhalla.route(
        [fix.point, for (final target in now.destinations) target.point],
        _profile,
        language: _texts.language,
        liveTraffic: settings.liveTraffic,
        avoidMotorways: settings.avoidMotorways,
        avoidTolls: settings.avoidTolls,
        avoidFerries: settings.avoidFerries,
        alternatives: false,
        heading: fix.heading,
        cancel: cancel,
      );
      final current = state;
      if (cancel.isCancelled || current == null || routes.isEmpty) return;
      _suggestionExpiry?.cancel();
      _newRoute(routes.first, current.destinations);
      // Apply the latest fix right away, otherwise nothing shows until the next.
      if (state?.fix case final latest?) _onFix(latest);
    } on DioException {
      // No network: the old route stays, try again in ten seconds.
      state = state?.copyWith(recalculating: false);
    } on RouteError {
      state = state?.copyWith(recalculating: false);
    }
  }
}

final navigationProvider =
    NotifierProvider<NavigationNotifier, NavigationState?>(
      NavigationNotifier.new,
    );
