// The contract between Dart and the car screens (Android Auto and CarPlay).
// Regenerate with `dart run pigeon --input pigeons/car.dart`; the output is
// checked in.
//
// Dart is the source of truth: it plans, navigates and speaks. Native draws
// the map with MapLibre and fills the car templates with what it gets here,
// and reports what the user does in the car.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/car/car_api.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/nl/g4d/homemaps/car/CarApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'nl.g4d.homemaps.car'),
    swiftOut: 'ios/Runner/CarPlay/CarApi.g.swift',
    dartPackageName: 'homemaps',
  ),
)
/// What the maneuver is, grouped like the phone's icons. Native maps this to
/// its own maneuver type; the icon itself comes from Dart (see registerImage).
enum CarManeuverType {
  depart,
  destination,
  destinationLeft,
  destinationRight,
  straight,
  nameChange,
  slightRight,
  right,
  sharpRight,
  uturnRight,
  uturnLeft,
  sharpLeft,
  left,
  slightLeft,
  onRampStraight,
  onRampRight,
  onRampLeft,
  offRampRight,
  offRampLeft,
  keepStraight,
  keepRight,
  keepLeft,
  merge,
  mergeRight,
  mergeLeft,
  roundabout,
  roundaboutExit,
  ferryEnter,
  ferryExit,
}

/// A destination to pick: home, work, a recent one or a search result.
class CarPlace {
  CarPlace({
    required this.id,
    required this.label,
    required this.detail,
    required this.lat,
    required this.lon,
    required this.kind,
  });

  /// Dart's key for [CarFlutterApi.placeChosen].
  String id;
  String label;
  String detail;
  double lat;
  double lon;

  /// `home`, `work`, `recent` or `search`.
  String kind;
}

/// One route to choose from in the preview.
class CarRouteSummary {
  CarRouteSummary({
    required this.index,
    required this.via,
    required this.meters,
    required this.seconds,
    required this.delaySeconds,
    required this.hasToll,
    required this.hasFerry,
  });

  int index;

  /// "via A12, A27", or empty.
  String via;
  double meters;
  double seconds;

  /// Extra time because of traffic, 0 if none.
  double delaySeconds;
  bool hasToll;
  bool hasFerry;
}

/// The sign at an exit: number, road numbers and directions.
class CarRoadSign {
  CarRoadSign({
    required this.exit,
    required this.roads,
    required this.directions,
    required this.label,
  });

  String? exit;
  List<String> roads;
  List<String> directions;
  String? label;
}

/// One lane, as OSRM names the directions ("left", "slight right", ...).
class CarLane {
  CarLane({
    required this.directions,
    required this.correct,
    required this.usage,
  });

  List<String> directions;

  /// This lane is one you can use for the maneuver.
  bool correct;

  /// The direction you take in this lane, if it is a correct one.
  String? usage;
}

/// The next maneuver, as the car shows it.
class CarManeuver {
  CarManeuver({
    required this.type,
    required this.instruction,
    required this.shortAction,
    required this.streets,
    required this.roundaboutExit,
    required this.roundaboutAngle,
    required this.sign,
    required this.signIconKey,
    required this.iconKey,
    required this.metersToNext,
    required this.then,
    required this.lanes,
    required this.lanesIconKey,
    required this.lanesAhead,
  });

  CarManeuverType type;

  /// The full sentence ("Turn right onto Main Street").
  String instruction;

  /// Briefly what you do at a ramp or fork ("Keep left"), or null.
  String? shortAction;
  List<String> streets;
  int? roundaboutExit;

  /// Where you leave the roundabout, clockwise from straight on (degrees).
  double? roundaboutAngle;
  CarRoadSign? sign;

  /// The sign as an image (shields and directions, as the phone's panel),
  /// registered earlier; null without a sign.
  String? signIconKey;

  /// An image registered earlier with [CarHostApi.registerImage].
  String iconKey;

  /// Already rounded so it doesn't change every meter.
  double metersToNext;

  /// The maneuver right after this one, if it follows within a few hundred
  /// meters: at most one. (A list, not a nullable field: Swift structs can't
  /// contain themselves.)
  List<CarManeuver> then;
  List<CarLane>? lanes;

  /// The lane bar as an image, registered earlier.
  String? lanesIconKey;

  /// How far the lanes' junction is, if that isn't the maneuver itself.
  double? lanesAhead;
}

/// The trip as a whole: where to, how far, how long.
class CarTrip {
  CarTrip({
    required this.destinationLabel,
    required this.remainingMeters,
    required this.remainingSeconds,
    required this.etaEpochMs,
  });

  String destinationLabel;
  double remainingMeters;
  double remainingSeconds;
  int etaEpochMs;
}

class CarSpeed {
  CarSpeed({
    required this.limitKmh,
    required this.limitSource,
    required this.speedMs,
    required this.cameraIconKey,
    required this.cameraText,
    required this.cameraDetail,
    required this.cameraOver,
    required this.matrixIconKey,
  });

  int? limitKmh;

  /// `osm`, `timeOfDay`, `roadworks` or `msi` (a red ring).
  String limitSource;
  double? speedMs;

  /// Above the speed limit: the next speed camera or the average speed check
  /// you're in. The icon (see [CarHostApi.registerImage]) and its text ("400
  /// m", "avg 97"), with a smaller line below ("2.3 km to go"); null if
  /// there's none.
  String? cameraIconKey;
  String? cameraText;
  String? cameraDetail;

  /// Your average in the section is above its limit: the sign goes red.
  bool cameraOver;

  /// The next gantry's matrix signs (MSI) as one image, registered earlier;
  /// null when there is none ahead. Shown where the lanes go, instead of them.
  String? matrixIconKey;
}

class CarPosition {
  CarPosition({
    required this.lat,
    required this.lon,
    required this.heading,
    required this.speed,
    required this.accuracy,
  });

  double lat;
  double lon;
  double? heading;
  double? speed;
  double accuracy;
}

class CarCamera {
  CarCamera({
    required this.lat,
    required this.lon,
    required this.zoom,
    required this.bearing,
    required this.tilt,
    required this.animateMs,
  });

  double lat;
  double lon;
  double zoom;
  double bearing;
  double tilt;
  int animateMs;
}

class CarBounds {
  CarBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  double south;
  double west;
  double north;
  double east;
}

/// The car's screen.
class CarSurface {
  CarSurface({
    required this.width,
    required this.height,
    required this.density,
    required this.dark,
    required this.platform,
  });

  double width;
  double height;
  double density;
  bool dark;

  /// `androidauto` or `carplay`.
  String platform;
}

/// A question to the driver, like a faster route.
class CarAlert {
  CarAlert({
    required this.id,
    required this.title,
    required this.text,
    required this.accept,
    required this.reject,
    required this.seconds,
  });

  String id;
  String title;
  String text;
  String accept;
  String reject;

  /// After this it disappears by itself.
  int seconds;
}

/// Dart to the car. Native ignores everything while no car is connected.
@HostApi()
abstract class CarHostApi {
  /// Dart's handlers are in place; native replays a connection that happened
  /// before this.
  void ready();

  /// The labels of the templates in the user's language, by key (see
  /// `CarBridge.texts`), so the translations stay in one place.
  void setTexts(Map<String, String> texts);

  /// The map style: a URL, or the style itself as JSON (the night version).
  /// [dark]: it's a night style, so the map's backdrop is dark too.
  void setStyle(String style, bool isJson, bool dark);

  /// A PNG for the map (arrow head, location dot) or the templates (maneuver
  /// and lane icons), by key. [scale] is the pixel ratio it was drawn at.
  void registerImage(String key, Uint8List png, double scale);

  /// GeoJSON feature collections, as the phone draws them.
  void setRoutes(String geoJson);
  void setDriven(String geoJson);
  void setArrow(String geoJson);
  void setPosition(CarPosition position);

  /// The camera during navigation: over the position, in the direction of
  /// travel.
  void followCamera(CarCamera camera);
  void fitBounds(CarBounds bounds, double paddingPx);

  /// Whether the camera follows; off after the user moved the map.
  void setFollowing(bool following);

  /// The start screen: pick where to go. [locationOk]: the phone has a fix;
  /// otherwise the car asks for permission or tells the driver to open the
  /// app.
  void showHome(
    List<CarPlace> favourites,
    List<CarPlace> recents,
    bool locationOk,
  );

  /// The routes to choose from, after a place was picked.
  void showRoutePreview(
    String destinationLabel,
    List<CarRouteSummary> routes,
    int chosen,
  );
  void showLoading(bool loading);
  void showMessage(String title, String text);

  void startNavigation(CarTrip trip);
  void updateManeuver(CarManeuver next, CarTrip trip);

  /// Your speed, the limit and what's ahead on the road: every fix on which
  /// something of it changed, apart from the maneuver.
  void setSpeed(CarSpeed speed);
  void setRecalculating(bool recalculating);
  void showArrived(String destinationLabel);
  void endNavigation();
  void setMuted(bool muted);

  void showAlert(CarAlert alert);
  void dismissAlert(String id);
}

/// The car to Dart: what the driver does.
@FlutterApi()
abstract class CarFlutterApi {
  void connected(CarSurface surface);
  void disconnected();

  /// The screen size or dark mode changed.
  void surfaceChanged(CarSurface surface);

  void placeChosen(String id);

  @async
  List<CarPlace> search(String text);
  void routeChosen(int index);
  void startTrip();
  void stopTrip();
  void toggleMute();

  /// The driver panned or zoomed: following stops.
  void userMovedMap();
  void recenter();
  void alertAnswered(String id, bool accepted);

  /// Android's test drive (the review requires it): a fake GPS drives the
  /// route.
  void autoDriveEnabled();

  /// A `geo:` or navigation intent in the car: a point with a name, or a
  /// search text.
  void navigateTo(double? lat, double? lon, String? label, String? query);
  void backToHome();
}
