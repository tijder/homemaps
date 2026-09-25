import Flutter
import UIKit

/// What CarPlay shows, as Dart pushed it (see `CarHostApi` in car.dart), and
/// the way back to Dart for what the driver does. The scene delegate listens
/// for changes; while no car is connected the state just waits here.
final class CarHost: CarHostApi {
  static let shared = CarHost()

  enum Screen { case home, preview, navigating, arrived }

  private var flutter: CarFlutterApi?
  private var dartReady = false
  private var connectedSurface: CarSurface?
  weak var listener: CarHostListener?

  private(set) var texts: [String: String] = [:]
  private(set) var style: String?
  private(set) var styleIsJson = false
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

  // MARK: - To Dart

  private func call(_ name: String, _ block: @escaping (CarFlutterApi) async throws -> Void) {
    guard let api = flutter else { return }
    Task { @MainActor in
      do { try await block(api) } catch { NSLog("CarHost: \(name) failed: \(error)") }
    }
  }

  func surfaceAvailable(_ surface: CarSurface) {
    let first = connectedSurface == nil
    connectedSurface = surface
    NSLog("CarHost: surface %dx%d, dart %@", Int(surface.width), Int(surface.height), dartReady ? "ready" : "not ready yet")
    guard dartReady else { return }
    if first {
      call("connected") { try await $0.connected(surface: surface) }
    } else {
      call("surfaceChanged") { try await $0.surfaceChanged(surface: surface) }
    }
  }

  func surfaceGone() {
    connectedSurface = nil
    images.removeAll()
    if dartReady { call("disconnected") { try await $0.disconnected() } }
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
    NSLog("CarHost: dart ready, surface %@", connectedSurface == nil ? "none" : "connected")
    if let surface = connectedSurface {
      call("connected") { try await $0.connected(surface: surface) }
    }
  }

  func setTexts(texts: [String: String]) throws {
    self.texts = texts
    listener?.hostScreenChanged()
  }

  func setStyle(style: String, isJson: Bool) throws {
    self.style = style
    styleIsJson = isJson
    listener?.hostStyleChanged()
  }

  func registerImage(key: String, png: FlutterStandardTypedData, scale: Double) throws {
    guard let image = UIImage(data: png.data, scale: CGFloat(scale)) else { return }
    images[key] = image
    listener?.hostImageAdded(key)
  }

  func setRoutes(geoJson: String) throws {
    routesGeoJson = geoJson
    listener?.hostRoutesChanged()
  }

  func setDriven(geoJson: String) throws {
    drivenGeoJson = geoJson
    listener?.hostDrivenChanged()
  }

  func setArrow(geoJson: String) throws {
    arrowGeoJson = geoJson
    listener?.hostArrowChanged()
  }

  func setPosition(position: CarPosition) throws {
    self.position = position
    listener?.hostPositionChanged()
  }

  func followCamera(camera: CarCamera) throws { listener?.hostCamera(camera) }

  func fitBounds(bounds: CarBounds, paddingPx: Double) throws {
    listener?.hostFitBounds(bounds, padding: paddingPx)
  }

  func setFollowing(following: Bool) throws {
    self.following = following
    listener?.hostFollowingChanged()
  }

  func showHome(favourites: [CarPlace], recents: [CarPlace], locationOk: Bool) throws {
    self.favourites = favourites
    self.recents = recents
    self.locationOk = locationOk
    homeShown = true
    screen = .home
    loading = false
    message = nil
    listener?.hostScreenChanged()
  }

  func showRoutePreview(destinationLabel: String, routes: [CarRouteSummary], chosen: Int64) throws {
    previewLabel = destinationLabel
    previewRoutes = routes
    previewChosen = Int(chosen)
    screen = .preview
    loading = false
    message = nil
    listener?.hostScreenChanged()
  }

  func showLoading(loading: Bool) throws {
    self.loading = loading
    if loading && screen == .home { screen = .preview }
    listener?.hostScreenChanged()
  }

  func showMessage(title: String, text: String) throws {
    message = (title, text)
    loading = false
    listener?.hostScreenChanged()
  }

  func startNavigation(trip: CarTrip) throws {
    self.trip = trip
    maneuver = nil
    arrivedAt = nil
    recalculating = false
    screen = .navigating
    message = nil
    listener?.hostScreenChanged()
  }

  func updateManeuver(next: CarManeuver, trip: CarTrip, speed: CarSpeed) throws {
    maneuver = next
    self.trip = trip
    self.speed = speed
    listener?.hostManeuverChanged()
  }

  func setRecalculating(recalculating: Bool) throws {
    self.recalculating = recalculating
    listener?.hostManeuverChanged()
  }

  func showArrived(destinationLabel: String) throws {
    arrivedAt = destinationLabel
    screen = .arrived
    listener?.hostScreenChanged()
  }

  func endNavigation() throws {
    trip = nil
    maneuver = nil
    speed = nil
    arrivedAt = nil
    alert = nil
    screen = .home
    listener?.hostAlertChanged()
    listener?.hostScreenChanged()
  }

  func setMuted(muted: Bool) throws {
    self.muted = muted
    listener?.hostScreenChanged()
  }

  func showAlert(alert: CarAlert) throws {
    self.alert = alert
    listener?.hostAlertChanged()
  }

  func dismissAlert(id: String) throws {
    guard alert?.id == id else { return }
    alert = nil
    listener?.hostAlertChanged()
  }
}

/// Whoever shows the car screen (the CarPlay scene) hears what changed.
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
  func hostAlertChanged()
}
