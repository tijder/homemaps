import CarPlay
import MapKit
import UIKit

/// CarPlay: the map in the window, the templates around it, and everything
/// Dart pushes through `CarHost` shown on them.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPMapTemplateDelegate,
  CPSearchTemplateDelegate, CarHostListener
{
  private var interfaceController: CPInterfaceController?
  private var window: CPWindow?
  private var mapVC: CarPlayMapViewController?
  private var mapTemplate: CPMapTemplate?
  private var session: CPNavigationSession?
  private var trip: CPTrip?
  private var previewTrip: CPTrip?
  private var shownPreviewKey = ""
  private var alertShown: CPNavigationAlert?
  private var shownScreen: CarHost.Screen?
  private var shownManeuverKey: String?
  private var searchResults: [CarPlace] = []
  private var host: CarHost { CarHost.shared }

  // MARK: - Scene

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController,
    to window: CPWindow
  ) {
    self.interfaceController = interfaceController
    self.window = window
    let mapVC = CarPlayMapViewController()
    mapVC.onAppearanceChanged = { [weak self] in self?.reportSurface(first: false) }
    window.rootViewController = mapVC
    self.mapVC = mapVC
    let template = CPMapTemplate()
    template.mapDelegate = self
    template.automaticallyHidesNavigationBar = true
    mapTemplate = template
    host.listener = self
    interfaceController.setRootTemplate(template, animated: false, completion: nil)
    shownScreen = nil
    hostScreenChanged()
    DispatchQueue.main.async { self.reportSurface(first: true) }
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController, from window: CPWindow
  ) {
    if host.listener === self { host.listener = nil }
    session = nil
    trip = nil
    self.interfaceController = nil
    mapTemplate = nil
    mapVC = nil
    self.window = nil
    host.surfaceGone()
  }

  private func reportSurface(first: Bool) {
    guard let window = window, let mapVC = mapVC else { return }
    host.surfaceAvailable(
      CarSurface(
        width: window.bounds.width * window.screen.scale, height: window.bounds.height * window.screen.scale,
        density: window.screen.scale, dark: mapVC.isDark, platform: "carplay"))
  }

  // MARK: - Templates

  private func barButton(_ title: String, _ handler: @escaping () -> Void) -> CPBarButton {
    CPBarButton(title: title) { _ in handler() }
  }

  private func barButton(image: UIImage, _ handler: @escaping () -> Void) -> CPBarButton {
    CPBarButton(image: image) { _ in handler() }
  }

  private func mapButton(_ symbol: String, _ handler: @escaping () -> Void) -> CPMapButton {
    let button = CPMapButton { _ in handler() }
    button.image = UIImage(systemName: symbol)
    return button
  }

  private var mapButtons: [CPMapButton] {
    [
      mapButton("location.fill") { [weak self] in self?.host.recenter() },
      mapButton("plus.magnifyingglass") { [weak self] in self?.mapVC?.zoom(by: 1); self?.host.userMovedMap() },
      mapButton("minus.magnifyingglass") { [weak self] in self?.mapVC?.zoom(by: -1); self?.host.userMovedMap() },
      mapButton("arrow.up.and.down.and.arrow.left.and.right") { [weak self] in
        self?.mapTemplate?.showPanningInterface(animated: true)
      },
    ]
  }

  /// The root map template's bar and buttons for what Dart shows now.
  private func configureMapTemplate() {
    guard let template = mapTemplate else { return }
    template.mapButtons = mapButtons
    switch host.screen {
    case .home:
      template.leadingNavigationBarButtons = [
        barButton(image: UIImage(systemName: "magnifyingglass") ?? UIImage()) { [weak self] in self?.pushSearch() }
      ]
      template.trailingNavigationBarButtons = [
        barButton(host.text("whereTo")) { [weak self] in self?.pushDestinations() }
      ]
    case .preview:
      template.leadingNavigationBarButtons = [
        barButton(image: UIImage(systemName: "xmark") ?? UIImage()) { [weak self] in self?.host.backToHome() }
      ]
      template.trailingNavigationBarButtons = []
    case .navigating:
      template.leadingNavigationBarButtons = [
        barButton(host.text("stop")) { [weak self] in self?.host.stopTrip() }
      ]
      template.trailingNavigationBarButtons = [
        barButton(image: UIImage(systemName: host.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") ?? UIImage())
        { [weak self] in self?.host.toggleMute() }
      ]
    case .arrived:
      template.leadingNavigationBarButtons = [
        barButton(host.text("stop")) { [weak self] in self?.host.stopTrip() }
      ]
      template.trailingNavigationBarButtons = []
    }
  }

  private func listItem(_ place: CarPlace, symbol: String) -> CPListItem {
    let item = CPListItem(
      text: place.label.isEmpty ? host.text(place.kind) : place.label,
      detailText: place.detail.isEmpty ? nil : place.detail, image: UIImage(systemName: symbol))
    item.handler = { [weak self] _, completion in
      self?.host.placeChosen(place.id)
      self?.interfaceController?.popToRootTemplate(animated: true, completion: nil)
      completion()
    }
    return item
  }

  private func pushDestinations() {
    var items: [CPListItem] = []
    if !host.locationOk {
      let item = CPListItem(text: host.text("noLocation"), detailText: host.text("openApp"))
      item.handler = { _, completion in completion() }
      items.append(item)
    }
    for place in host.favourites {
      items.append(listItem(place, symbol: place.kind == "work" ? "briefcase.fill" : "house.fill"))
    }
    var sections = [CPListSection(items: items)]
    if !host.recents.isEmpty {
      sections.append(
        CPListSection(items: host.recents.map { listItem($0, symbol: "clock") }, header: host.text("recent"),
          sectionIndexTitle: nil))
    }
    let template = CPListTemplate(title: host.text("whereTo"), sections: sections)
    template.emptyViewTitleVariants = [host.text("search")]
    interfaceController?.pushTemplate(template, animated: true, completion: nil)
  }

  private func pushSearch() {
    let template = CPSearchTemplate()
    template.delegate = self
    interfaceController?.pushTemplate(template, animated: true, completion: nil)
  }

  private func showPreview() {
    guard let template = mapTemplate, !host.previewRoutes.isEmpty else { return }
    // The same routes again (a loading flag toggled): leave the preview alone.
    let key = host.previewLabel + host.previewRoutes.map { "\($0.meters)/\($0.seconds)" }.joined(separator: ",")
    if key == shownPreviewKey && previewTrip != nil { return }
    shownPreviewKey = key
    let destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0)))
    destination.name = host.previewLabel
    let origin = MKMapItem.forCurrentLocation()
    let choices = host.previewRoutes.map { route -> CPRouteChoice in
      var details = [Distance.format(route.meters)]
      if route.delaySeconds >= 60 { details.append("+\(Distance.duration(route.delaySeconds)) \(host.text("delay"))") }
      if route.hasToll { details.append(host.text("toll")) }
      if route.hasFerry { details.append(host.text("ferry")) }
      let summary = route.via.isEmpty ? host.text("fastest") : route.via
      return CPRouteChoice(
        summaryVariants: [summary], additionalInformationVariants: [details.joined(separator: " · ")],
        selectionSummaryVariants: [Distance.duration(route.seconds)])
    }
    let trip = CPTrip(origin: origin, destination: destination, routeChoices: choices)
    previewTrip = trip
    let text = CPTripPreviewTextConfiguration(
      startButtonTitle: host.text("start"), additionalRoutesButtonTitle: host.text("routes"),
      overviewButtonTitle: host.text("routes"))
    template.showTripPreviews([trip], textConfiguration: text)
  }

  private func showMessage(_ title: String, _ text: String) {
    let alert = CPAlertTemplate(
      titleVariants: [text.isEmpty ? title : "\(title)\n\(text)"],
      actions: [
        CPAlertAction(title: host.text("whereTo"), style: .default) { [weak self] _ in
          self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
          self?.host.backToHome()
        }
      ])
    interfaceController?.presentTemplate(alert, animated: true, completion: nil)
  }

  private func startSession() {
    guard let template = mapTemplate, let carTrip = host.trip else { return }
    template.hideTripPreviews()
    let trip: CPTrip
    if let preview = previewTrip {
      trip = preview
    } else {
      let destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0)))
      destination.name = carTrip.destinationLabel
      trip = CPTrip(origin: MKMapItem.forCurrentLocation(), destination: destination, routeChoices: [CPRouteChoice(summaryVariants: [""], additionalInformationVariants: [""], selectionSummaryVariants: [""])])
    }
    previewTrip = nil
    shownPreviewKey = ""
    self.trip = trip
    session = template.startNavigationSession(for: trip)
    shownManeuverKey = nil
    hostManeuverChanged()
  }

  private func endSession(finished: Bool) {
    if finished { session?.finishTrip() } else { session?.cancelTrip() }
    session = nil
    trip = nil
    mapTemplate?.hideTripPreviews()
    shownManeuverKey = nil
  }

  // MARK: - CarHostListener

  func hostStyleChanged() { mapVC?.loadStyle() }
  func hostImageAdded(_ key: String) {
    mapVC?.imageAdded(key)
    // A maneuver that was waiting for its icon.
    if key == host.maneuver?.iconKey || key == host.maneuver?.then?.iconKey { shownManeuverKey = nil; hostManeuverChanged() }
  }
  func hostRoutesChanged() { mapVC?.routesChanged() }
  func hostDrivenChanged() { mapVC?.drivenChanged() }
  func hostArrowChanged() { mapVC?.arrowChanged() }
  func hostPositionChanged() { mapVC?.positionChanged() }
  func hostCamera(_ camera: CarCamera) { mapVC?.apply(camera) }
  func hostFitBounds(_ bounds: CarBounds, padding: Double) { mapVC?.fit(bounds, padding: padding) }
  func hostFollowingChanged() { mapVC?.applyInsets() }

  func hostScreenChanged() {
    configureMapTemplate()
    let screen = host.screen
    if let message = host.message, screen == .preview {
      showMessage(message.title, message.text)
    }
    guard screen != shownScreen else {
      if screen == .preview { showPreview() }
      return
    }
    let previous = shownScreen
    shownScreen = screen
    switch screen {
    case .home:
      if previous == .navigating || previous == .arrived { endSession(finished: previous == .arrived) }
      previewTrip = nil
      shownPreviewKey = ""
      mapTemplate?.hideTripPreviews()
      interfaceController?.popToRootTemplate(animated: true, completion: nil)
      mapVC?.speedChanged()
    case .preview:
      interfaceController?.popToRootTemplate(animated: true, completion: nil)
      showPreview()
    case .navigating:
      interfaceController?.popToRootTemplate(animated: true, completion: nil)
      startSession()
    case .arrived:
      session?.finishTrip()
      let alert = CPNavigationAlert(
        titleVariants: [host.text("arrived")], subtitleVariants: [host.arrivedAt ?? ""], image: nil,
        primaryAction: CPAlertAction(title: host.text("stop"), style: .default) { [weak self] _ in self?.host.stopTrip() },
        secondaryAction: nil, duration: 0)
      mapTemplate?.present(navigationAlert: alert, animated: true)
      mapVC?.speedChanged()
    }
  }

  func hostManeuverChanged() {
    guard let session = session, let template = mapTemplate, let trip = trip else { return }
    mapVC?.speedChanged()
    if host.recalculating {
      if shownManeuverKey != "recalculating" {
        shownManeuverKey = "recalculating"
        session.pauseTrip(for: .rerouting, description: host.text("recalculating"))
      }
      return
    }
    guard let next = host.maneuver else { return }
    if let carTrip = host.trip {
      template.update(
        ManeuverBuilder.estimates(meters: carTrip.remainingMeters, seconds: carTrip.remainingSeconds), for: trip,
        with: .default)
    }
    let key = "\(next.iconKey)|\(next.instruction)|\(next.then?.instruction ?? "")|\(next.lanesIconKey ?? "")"
    if key != shownManeuverKey {
      shownManeuverKey = key
      var maneuvers = [ManeuverBuilder.maneuver(next)]
      if let then = next.then { maneuvers.append(ManeuverBuilder.maneuver(then)) }
      if #available(iOS 17.4, *), let lanes = next.lanes, !lanes.isEmpty {
        let guidance = ManeuverBuilder.laneGuidance(lanes, instruction: next.shortAction ?? next.instruction)
        session.add([guidance])
        maneuvers[0].linkedLaneGuidance = guidance
      }
      session.upcomingManeuvers = maneuvers
    }
    if let first = session.upcomingManeuvers.first {
      session.updateEstimates(ManeuverBuilder.estimates(meters: next.metersToNext, seconds: 0), for: first)
    }
  }

  func hostAlertChanged() {
    guard let template = mapTemplate else { return }
    if alertShown != nil, host.alert == nil {
      template.dismissNavigationAlert(animated: true) { _ in }
      alertShown = nil
      return
    }
    guard let alert = host.alert, alertShown == nil else { return }
    let navigationAlert = CPNavigationAlert(
      titleVariants: [alert.title], subtitleVariants: [alert.text], image: nil,
      primaryAction: CPAlertAction(title: alert.accept, style: .default) { [weak self] _ in
        self?.alertShown = nil
        self?.host.alertAnswered(alert.id, accepted: true)
      },
      secondaryAction: CPAlertAction(title: alert.reject, style: .cancel) { [weak self] _ in
        self?.alertShown = nil
        self?.host.alertAnswered(alert.id, accepted: false)
      }, duration: TimeInterval(alert.seconds))
    alertShown = navigationAlert
    template.present(navigationAlert: navigationAlert, animated: true)
  }

  // MARK: - CPMapTemplateDelegate

  func mapTemplate(_ mapTemplate: CPMapTemplate, selectedPreviewFor trip: CPTrip, using routeChoice: CPRouteChoice) {
    if let index = trip.routeChoices.firstIndex(of: routeChoice) { host.routeChosen(index) }
  }

  func mapTemplate(_ mapTemplate: CPMapTemplate, startedTrip trip: CPTrip, using routeChoice: CPRouteChoice) {
    if let index = trip.routeChoices.firstIndex(of: routeChoice) { host.routeChosen(index) }
    host.startTrip()
  }

  func mapTemplateDidCancelNavigation(_ mapTemplate: CPMapTemplate) {
    host.stopTrip()
  }

  func mapTemplateDidBeginPanGesture(_ mapTemplate: CPMapTemplate) {
    host.userMovedMap()
  }

  func mapTemplate(_ mapTemplate: CPMapTemplate, didUpdatePanGestureWithTranslation translation: CGPoint, velocity: CGPoint) {
    mapVC?.pan(by: translation)
  }

  func mapTemplate(_ mapTemplate: CPMapTemplate, panWith direction: CPMapTemplate.PanDirection) {
    var translation = CGPoint.zero
    let step: CGFloat = 80
    if direction.contains(.left) { translation.x = step }
    if direction.contains(.right) { translation.x = -step }
    if direction.contains(.up) { translation.y = step }
    if direction.contains(.down) { translation.y = -step }
    host.userMovedMap()
    mapVC?.pan(by: translation)
  }

  func mapTemplateDidDismissPanningInterface(_ mapTemplate: CPMapTemplate) {}

  func mapTemplate(_ mapTemplate: CPMapTemplate, displayStyleFor maneuver: CPManeuver) -> CPManeuverDisplayStyle {
    .leadingSymbol
  }

  // MARK: - CPSearchTemplateDelegate

  func searchTemplate(
    _ searchTemplate: CPSearchTemplate, updatedSearchText searchText: String,
    completionHandler: @escaping ([CPListItem]) -> Void
  ) {
    host.search(searchText) { [weak self] found in
      guard let self = self else { return completionHandler([]) }
      self.searchResults = found
      completionHandler(
        found.map { place in
          let item = CPListItem(text: place.label, detailText: place.detail.isEmpty ? nil : place.detail)
          item.userInfo = place.id
          return item
        })
    }
  }

  func searchTemplate(
    _ searchTemplate: CPSearchTemplate, selectedResult item: CPListItem, completionHandler: @escaping () -> Void
  ) {
    if let id = item.userInfo as? String { host.placeChosen(id) }
    interfaceController?.popToRootTemplate(animated: true, completion: nil)
    completionHandler()
  }

  func searchTemplateSearchButtonPressed(_ searchTemplate: CPSearchTemplate) {}
}

/// Distances and durations as the phone shows them.
enum Distance {
  static func format(_ meters: Double) -> String {
    if meters < 1000 { return "\(Int(meters)) m" }
    if meters < 10000 { return String(format: "%.1f km", meters / 1000) }
    return "\(Int(meters / 1000)) km"
  }

  static func duration(_ seconds: Double) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes) min" }
    return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
  }
}
