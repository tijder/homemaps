import Flutter
import UIKit

/// What CarPlay shows, as Dart pushed it (see `CarHostApi` in car.dart), and
/// the way back to Dart for what the driver does. The scene delegates (the
/// app's window and the dashboard) listen for changes; while no car is
/// connected the state just waits here.
final class CarHost: CarHostApi {
  static let shared = CarHost()

  enum Screen { case home, preview, navigating, arrived }

  private var flutter: CarFlutterApi?
  private var dartReady = false

  /// The app's window and the dashboard's, as they are connected. Dart hears
  /// of one surface: the app's, or else the dashboard's.
  private var mainSurface: CarSurface?
  private var dashboardSurface: CarSurface?
  private var reportedSurface: CarSurface?
  private let listeners = NSHashTable<AnyObject>.weakObjects()

  private(set) var texts: [String: String] = [:]
  private(set) var style: String?
  private(set) var styleIsJson = false
  private(set) var styleDark = false
  private(set) var images: [String: UIImage] = [:]
  private(set) var routesGeoJson: String?
  private(set) var drivenGeoJson: String?
  private(set) var arrowGeoJson: String?
  private(set) var position: CarPosition?
  private(set) var following = true

  private(set) var screen = Screen.home
  private(set) var favourites: [CarPlace] = []
  private(set) var recents: [CarPlace] = []
  private(set) var locationOk = false
  private(set) var homeShown = false
  private(set) var previewLabel = ""
  private(set) var previewRoutes: [CarRouteSummary] = []
  private(set) var previewChosen = 0
  private(set) var loading = false
  private(set) var message: (title: String, text: String)?
  private(set) var trip: CarTrip?
  private(set) var maneuver: CarManeuver?
  private(set) var speed: CarSpeed?
  private(set) var recalculating = false
  private(set) var arrivedAt: String?
  private(set) var muted = false
  private(set) var alert: CarAlert?

  func text(_ key: String) -> String { texts[key] ?? key }

  func attach(engine: FlutterEngine) {
    CarHostApiSetup.setUp(binaryMessenger: engine.binaryMessenger, api: self)
    flutter = CarFlutterApi(binaryMessenger: engine.binaryMessenger)
  }

  func addListener(_ listener: CarHostListener) { listeners.add(listener) }
  func removeListener(_ listener: CarHostListener) { listeners.remove(listener) }

  private func each(_ block: (CarHostListener) -> Void) {
    for object in listeners.allObjects {
      if let listener = object as? CarHostListener { block(listener) }
    }
  }

  // MARK: - To Dart

  private func call(_ name: String, _ block: @escaping (CarFlutterApi) async throws -> Void) {
    guard let api = flutter else { return }
    Task { @MainActor in
      do { try await block(api) } catch { NSLog("CarHost: \(name) failed: \(error)") }
    }
  }

  func surfaceAvailable(_ surface: CarSurface, dashboard: Bool = false) {
    if dashboard { dashboardSurface = surface } else { mainSurface = surface }
    NSLog(
      "CarHost: %@ surface %dx%d, dart %@", dashboard ? "dashboard" : "app", Int(surface.width), Int(surface.height),
      dartReady ? "ready" : "not ready yet")
    syncSurface()
  }

  func surfaceGone(dashboard: Bool = false) {
    if dashboard { dashboardSurface = nil } else { mainSurface = nil }
    NSLog("CarHost: %@ surface gone", dashboard ? "dashboard" : "app")
    syncSurface()
  }

  /// Dart hears of a connection once, of a change of window, and of the
  /// last window going.
  private func syncSurface() {
    guard dartReady else { return }
    let wanted = mainSurface ?? dashboardSurface
    guard let surface = wanted else {
      if reportedSurface != nil {
        reportedSurface = nil
        images.removeAll()
        call("disconnected") { try await $0.disconnected() }
      }
      return
    }
    if reportedSurface == nil {
      reportedSurface = surface
      call("connected") { try await $0.connected(surface: surface) }
    } else if reportedSurface != surface {
      reportedSurface = surface
      call("surfaceChanged") { try await $0.surfaceChanged(surface: surface) }
    }
  }

  func placeChosen(_ id: String) { call("placeChosen") { try await $0.placeChosen(id: id) } }
  func routeChosen(_ index: Int) { call("routeChosen") { try await $0.routeChosen(index: Int64(index)) } }
  func startTrip() { call("startTrip") { try await $0.startTrip() } }
  func stopTrip() { call("stopTrip") { try await $0.stopTrip() } }
  func toggleMute() { call("toggleMute") { try await $0.toggleMute() } }
  func userMovedMap() {
    following = false
    call("userMovedMap") { try await $0.userMovedMap() }
  }
  func recenter() { call("recenter") { try await $0.recenter() } }
  func alertAnswered(_ id: String, accepted: Bool) {
    call("alertAnswered") { try await $0.alertAnswered(id: id, accepted: accepted) }
  }
  func backToHome() { call("backToHome") { try await $0.backToHome() } }

  /// A search; [done] gets the results on the main thread.
  func search(_ text: String, done: @escaping ([CarPlace]) -> Void) {
    guard let api = flutter else { return done([]) }
    Task { @MainActor in
      do { done(try await api.search(text: text)) } catch {
        NSLog("CarHost: search failed: \(error)")
        done([])
      }
    }
  }

  // MARK: - From Dart (CarHostApi)

  func ready() throws {
    dartReady = true
    NSLog("CarHost: dart ready, surface %@", (mainSurface ?? dashboardSurface) == nil ? "none" : "connected")
    reportedSurface = nil
    syncSurface()
  }

  func setTexts(texts: [String: String]) throws {
    self.texts = texts
    each { $0.hostScreenChanged() }
  }

  func setStyle(style: String, isJson: Bool, dark: Bool) throws {
    self.style = style
    styleIsJson = isJson
    styleDark = dark
    each { $0.hostStyleChanged() }
  }

  func registerImage(key: String, png: FlutterStandardTypedData, scale: Double) throws {
    guard let image = UIImage(data: png.data, scale: CGFloat(scale)) else { return }
    images[key] = image
    each { $0.hostImageAdded(key) }
  }

  func setRoutes(geoJson: String) throws {
    routesGeoJson = geoJson
    each { $0.hostRoutesChanged() }
  }

  func setDriven(geoJson: String) throws {
    drivenGeoJson = geoJson
    each { $0.hostDrivenChanged() }
  }

  func setArrow(geoJson: String) throws {
    arrowGeoJson = geoJson
    each { $0.hostArrowChanged() }
  }

  func setPosition(position: CarPosition) throws {
    self.position = position
    each { $0.hostPositionChanged() }
  }

  func followCamera(camera: CarCamera) throws { each { $0.hostCamera(camera) } }

  func fitBounds(bounds: CarBounds, paddingPx: Double) throws {
    each { $0.hostFitBounds(bounds, padding: paddingPx) }
  }

  func setFollowing(following: Bool) throws {
    self.following = following
    each { $0.hostFollowingChanged() }
  }

  func showHome(favourites: [CarPlace], recents: [CarPlace], locationOk: Bool) throws {
    self.favourites = favourites
    self.recents = recents
    self.locationOk = locationOk
    homeShown = true
    screen = .home
    loading = false
    message = nil
    each { $0.hostScreenChanged() }
  }

  func showRoutePreview(destinationLabel: String, routes: [CarRouteSummary], chosen: Int64) throws {
    previewLabel = destinationLabel
    previewRoutes = routes
    previewChosen = Int(chosen)
    screen = .preview
    loading = false
    message = nil
    each { $0.hostScreenChanged() }
  }

  func showLoading(loading: Bool) throws {
    self.loading = loading
    if loading && screen == .home { screen = .preview }
    each { $0.hostScreenChanged() }
  }

  func showMessage(title: String, text: String) throws {
    message = (title, text)
    loading = false
    each { $0.hostScreenChanged() }
  }

  func startNavigation(trip: CarTrip) throws {
    self.trip = trip
    maneuver = nil
    arrivedAt = nil
    recalculating = false
    screen = .navigating
    message = nil
    each { $0.hostScreenChanged() }
  }

  func updateManeuver(next: CarManeuver, trip: CarTrip) throws {
    maneuver = next
    self.trip = trip
    each { $0.hostManeuverChanged() }
  }

  func setSpeed(speed: CarSpeed) throws {
    self.speed = speed
    each { $0.hostSpeedChanged() }
  }

  func setRecalculating(recalculating: Bool) throws {
    self.recalculating = recalculating
    each { $0.hostManeuverChanged() }
  }

  func showArrived(destinationLabel: String) throws {
    arrivedAt = destinationLabel
    screen = .arrived
    each { $0.hostScreenChanged() }
  }

  func endNavigation() throws {
    trip = nil
    maneuver = nil
    speed = nil
    arrivedAt = nil
    alert = nil
    screen = .home
    each { $0.hostAlertChanged() }
    each { $0.hostScreenChanged() }
  }

  func setMuted(muted: Bool) throws {
    self.muted = muted
    each { $0.hostScreenChanged() }
  }

  func showAlert(alert: CarAlert) throws {
    self.alert = alert
    each { $0.hostAlertChanged() }
  }

  func dismissAlert(id: String) throws {
    guard alert?.id == id else { return }
    alert = nil
    each { $0.hostAlertChanged() }
  }
}

/// Whoever shows the car screen (the CarPlay scene, the dashboard) hears
/// what changed.
protocol CarHostListener: AnyObject {
  func hostStyleChanged()
  func hostImageAdded(_ key: String)
  func hostRoutesChanged()
  func hostDrivenChanged()
  func hostArrowChanged()
  func hostPositionChanged()
  func hostCamera(_ camera: CarCamera)
  func hostFitBounds(_ bounds: CarBounds, padding: Double)
  func hostFollowingChanged()
  func hostScreenChanged()
  func hostManeuverChanged()
  func hostSpeedChanged()
  func hostAlertChanged()
}
