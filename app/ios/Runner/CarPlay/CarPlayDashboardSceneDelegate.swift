import CarPlay
import UIKit

/// CarPlay's dashboard: the small map next to the music and the calendar on
/// the car's home screen, with two buttons. CarPlay draws the next maneuver
/// there itself from the navigation session of the app's window; the map
/// here is ours, the same one as in the app's window, on the same state from
/// Dart. With this window the app stays CarPlay's navigation app (in the
/// sidebar, on the dashboard) while another app is in front.
final class CarPlayDashboardSceneDelegate: UIResponder, CPTemplateApplicationDashboardSceneDelegate, CarHostListener {
  private var dashboard: CPDashboardController?
  private var window: UIWindow?
  private var mapVC: CarPlayMapViewController?
  private var shownScreen: CarHost.Screen?
  private var shownMuted: Bool?
  private var host: CarHost { CarHost.shared }

  func templateApplicationDashboardScene(
    _ templateApplicationDashboardScene: CPTemplateApplicationDashboardScene,
    didConnect dashboardController: CPDashboardController, to window: UIWindow
  ) {
    NSLog("CarPlay dashboard: connected, window %@", NSCoder.string(for: window.bounds))
    dashboard = dashboardController
    self.window = window
    let mapVC = CarPlayMapViewController()
    mapVC.compact = true
    mapVC.onAppearanceChanged = { [weak self] in self?.reportSurface() }
    window.rootViewController = mapVC
    self.mapVC = mapVC
    host.addListener(self)
    shownScreen = nil
    shownMuted = nil
    hostScreenChanged()
    mapVC.applyInsets()
    DispatchQueue.main.async { self.reportSurface() }
  }

  func templateApplicationDashboardScene(
    _ templateApplicationDashboardScene: CPTemplateApplicationDashboardScene,
    didDisconnect dashboardController: CPDashboardController, from window: UIWindow
  ) {
    NSLog("CarPlay dashboard: disconnected")
    host.removeListener(self)
    dashboard = nil
    mapVC = nil
    self.window = nil
    host.surfaceGone(dashboard: true)
  }

  private func reportSurface() {
    guard let window = window, let mapVC = mapVC else { return }
    host.surfaceAvailable(
      CarSurface(
        width: window.bounds.width * window.screen.scale, height: window.bounds.height * window.screen.scale,
        density: window.screen.scale, dark: mapVC.isDark, platform: "carplay"),
      dashboard: true)
  }

  /// At most two buttons: while navigating stop and the voice.
  private func configureButtons() {
    guard let dashboard = dashboard else { return }
    let screen = host.screen
    if screen == shownScreen && host.muted == shownMuted { return }
    shownScreen = screen
    shownMuted = host.muted
    guard screen == .navigating || screen == .arrived else {
      dashboard.shortcutButtons = []
      return
    }
    let stop = CPDashboardButton(
      titleVariants: [host.text("stop")], subtitleVariants: [""], image: UIImage(systemName: "xmark") ?? UIImage()
    ) { [weak self] _ in self?.host.stopTrip() }
    guard screen == .navigating else {
      dashboard.shortcutButtons = [stop]
      return
    }
    let voice = CPDashboardButton(
      titleVariants: [host.text(host.muted ? "unmute" : "mute")], subtitleVariants: [""],
      image: UIImage(systemName: host.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") ?? UIImage()
    ) { [weak self] _ in self?.host.toggleMute() }
    dashboard.shortcutButtons = [stop, voice]
  }

  // MARK: - CarHostListener

  func hostStyleChanged() { mapVC?.loadStyle() }
  func hostImageAdded(_ key: String) {
    mapVC?.imageAdded(key)
    if key == host.speed?.cameraIconKey { mapVC?.speedChanged() }
  }
  func hostRoutesChanged() { mapVC?.routesChanged() }
  func hostDrivenChanged() { mapVC?.drivenChanged() }
  func hostArrowChanged() { mapVC?.arrowChanged() }
  func hostPositionChanged() { mapVC?.positionChanged() }
  func hostCamera(_ camera: CarCamera) { mapVC?.apply(camera) }
  func hostFitBounds(_ bounds: CarBounds, padding: Double) { mapVC?.fit(bounds, padding: padding) }
  func hostFollowingChanged() { mapVC?.applyInsets() }
  func hostScreenChanged() {
    configureButtons()
    mapVC?.speedChanged()
  }
  func hostManeuverChanged() { mapVC?.lanesChanged() }
  func hostSpeedChanged() { mapVC?.speedChanged() }
  func hostAlertChanged() {}
}
