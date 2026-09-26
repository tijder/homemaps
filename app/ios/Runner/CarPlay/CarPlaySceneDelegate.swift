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
  private var shownMessage: String?
  private var host: CarHost { CarHost.shared }

  // MARK: - Interface operations
  //
  // CarPlay raises an NSException (and so kills the app) when a template
  // operation fails and no completion handler was given: a pop while the
  // root is still being set, a second push or present while the first one
  // animates. Every operation therefore goes through this queue, one at a
  // time, each with a completion that only logs a failure.

  private typealias Done = (Bool, Error?) -> Void
  private var operations: [(@escaping Done) -> Void] = []
  private var operationRunning = false

  private func enqueue(_ name: String, _ operation: @escaping (CPInterfaceController, @escaping Done) -> Void) {
    operations.append { [weak self] done in
      guard let controller = self?.interfaceController else { return done(false, nil) }
      operation(controller) { ok, error in
        if let error = error { NSLog("CarPlay: \(name) failed: \(error)") }
        done(ok, error)
      }
    }
    runNextOperation()
  }

  private func runNextOperation() {
    guard !operationRunning, !operations.isEmpty else { return }
    guard interfaceController != nil else { return operations.removeAll() }
    operationRunning = true
    let operation = operations.removeFirst()
    operation { [weak self] _, _ in
      DispatchQueue.main.async {
        self?.operationRunning = false
        self?.runNextOperation()
      }
    }
  }

  private func setRoot(_ template: CPTemplate) {
    enqueue("setRootTemplate") { controller, done in
      controller.setRootTemplate(template, animated: false, completion: done)
    }
  }

  private func push(_ template: CPTemplate) {
    enqueue("pushTemplate") { controller, done in
      // Already there (a double tap), or the stack is at CarPlay's limit.
      if let top = controller.topTemplate, type(of: top) == type(of: template) { return done(true, nil) }
      if controller.templates.count >= 5 { return done(true, nil) }
      controller.pushTemplate(template, animated: true, completion: done)
    }
  }

  private func popToRoot() {
    enqueue("popToRootTemplate") { controller, done in
      guard controller.templates.count > 1 else { return done(true, nil) }
      controller.popToRootTemplate(animated: true, completion: done)
    }
  }

  private func present(_ template: CPTemplate) {
    enqueue("presentTemplate") { controller, done in
      let show = { controller.presentTemplate(template, animated: true, completion: done) }
      if controller.presentedTemplate != nil {
        controller.dismissTemplate(animated: false) { _, _ in show() }
      } else {
        show()
      }
    }
  }

  private func dismissPresented() {
    enqueue("dismissTemplate") { controller, done in
      guard controller.presentedTemplate != nil else { return done(true, nil) }
      controller.dismissTemplate(animated: true, completion: done)
    }
  }

  // MARK: - Scene

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController,
    to window: CPWindow
  ) {
    NSLog("CarPlay: connected, window %@", NSCoder.string(for: window.bounds))
    self.interfaceController = interfaceController
    self.window = window
    let mapVC = CarPlayMapViewController()
    mapVC.onAppearanceChanged = { [weak self] in self?.reportSurface(first: false) }
    window.rootViewController = mapVC
    self.mapVC = mapVC
    let template = CPMapTemplate()
    template.mapDelegate = self
    template.automaticallyHidesNavigationBar = true
    // The instruction panel in the app's blue (the route line's colour; the
    // phone's header is the same family), not CarPlay's default. The icons
    // Dart draws are white for it.
    template.guidanceBackgroundColor = UIColor(hex: 0x1565c0)
    mapTemplate = template
    host.addListener(self)
    operations.removeAll()
    operationRunning = false
    setRoot(template)
    shownScreen = nil
    shownMessage = nil
    hostScreenChanged()
    DispatchQueue.main.async { self.reportSurface(first: true) }
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController, from window: CPWindow
  ) {
    host.removeListener(self)
    operations.removeAll()
    operationRunning = false
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
      self?.popToRoot()
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
    push(template)
  }

  private func pushSearch() {
    let template = CPSearchTemplate()
    template.delegate = self
    push(template)
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
          self?.shownMessage = nil
          self?.dismissPresented()
          self?.host.backToHome()
        }
      ])
    present(alert)
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
    // A maneuver that was waiting for its icon, or a sign for its image.
    if key == host.maneuver?.iconKey || key == host.maneuver?.then.first?.iconKey
      || key == host.maneuver?.signIconKey || key == host.maneuver?.lanesIconKey
    {
      shownManeuverKey = nil
      hostManeuverChanged()
    }
    if key == host.speed?.matrixIconKey || key == host.speed?.cameraIconKey { mapVC?.speedChanged() }
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
    // The message once; gone again when Dart clears it (a new preview, home).
    if let message = host.message, screen == .preview {
      let key = "\(message.title)\n\(message.text)"
      if key != shownMessage {
        shownMessage = key
        showMessage(message.title, message.text)
      }
    } else if shownMessage != nil {
      shownMessage = nil
      dismissPresented()
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
      popToRoot()
      mapVC?.speedChanged()
    case .preview:
      popToRoot()
      showPreview()
    case .navigating:
      popToRoot()
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

  func hostSpeedChanged() { mapVC?.speedChanged() }

  func hostManeuverChanged() {
    guard let session = session, let template = mapTemplate, let trip = trip else { return }
    mapVC?.lanesChanged()
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
    let key =
      "\(next.iconKey)|\(next.instruction)|\(next.then.first?.instruction ?? "")|\(next.lanesIconKey ?? "")|\(next.signIconKey ?? "")"
    if key != shownManeuverKey {
      shownManeuverKey = key
      NSLog(
        "CarPlay: maneuver %@, %ld lanes (%@), sign %@", next.instruction, next.lanes?.count ?? 0,
        next.lanesIconKey ?? "-", next.signIconKey ?? "-")
      var maneuvers = [ManeuverBuilder.maneuver(next)]
      if let then = next.then.first { maneuvers.append(ManeuverBuilder.maneuver(then)) }
      if #available(iOS 18.0, *), let lanes = next.lanes, !lanes.isEmpty {
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
    popToRoot()
    completionHandler()
  }

  func searchTemplateSearchButtonPressed(_ searchTemplate: CPSearchTemplate) {}
}

/// Distances and durations as the phone shows them ("2,6 km" in Dutch).
enum Distance {
  static func format(_ meters: Double) -> String {
    if meters < 1000 { return "\(Int(meters)) m" }
    if meters < 10000 {
      let formatter = NumberFormatter()
      formatter.locale = Locale.current
      formatter.minimumFractionDigits = 1
      formatter.maximumFractionDigits = 1
      return "\(formatter.string(from: NSNumber(value: meters / 1000)) ?? String(format: "%.1f", meters / 1000)) km"
    }
    return "\(Int(meters / 1000)) km"
  }

  static func duration(_ seconds: Double) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes) min" }
    return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
  }
}
