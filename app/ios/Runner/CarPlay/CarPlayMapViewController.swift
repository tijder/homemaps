import MapLibre
import UIKit

/// The map in the CarPlay window: MapLibre with our own style, and the
/// routes, the driven part, the turn arrow and the position from Dart as
/// GeoJSON, drawn with the same colours and widths as on the phone (see
/// `map_widget.dart`). CarPlay delivers no touches here; panning and zooming
/// come through the map template's buttons and pan callbacks.
final class CarPlayMapViewController: UIViewController, MLNMapViewDelegate {
  private static let empty = #"{"type":"FeatureCollection","features":[]}"#

  private(set) var mapView: MLNMapView!
  private var styleReady = false
  private var pendingCamera: CarCamera?
  private let speedLimit = SpeedLimitView()
  private let cameraSign = CameraSignView()

  /// Dark mode of the car's screen changed.
  var onAppearanceChanged: (() -> Void)?

  override func viewDidLoad() {
    super.viewDidLoad()
    // Opaque: without a loaded style the map view draws nothing, and the
    // car would show its wallpaper as if the app had no window at all.
    view.backgroundColor = UIColor(hex: 0xe0e0e0)
    view.isOpaque = true
    NSLog("CarPlay map: view loaded, %d x %d", Int(view.bounds.width), Int(view.bounds.height))
    let mapView = MLNMapView(frame: view.bounds)
    mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    mapView.delegate = self
    mapView.logoView.isHidden = true
    mapView.attributionButton.isHidden = true
    mapView.compassView.isHidden = true
    mapView.isUserInteractionEnabled = false
    view.addSubview(mapView)
    self.mapView = mapView
    speedLimit.isHidden = true
    view.addSubview(speedLimit)
    cameraSign.isHidden = true
    view.addSubview(cameraSign)
    loadStyle()
  }

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    applyInsets()
    let insets = view.safeAreaInsets
    speedLimit.frame = CGRect(
      x: insets.left + 12, y: view.bounds.height - insets.bottom - 12 - 56, width: 56, height: 56)
    speedChanged()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
      onAppearanceChanged?()
    }
  }

  var isDark: Bool { traitCollection.userInterfaceStyle == .dark }

  // MARK: - Style

  func loadStyle() {
    guard let mapView = mapView, let style = CarHost.shared.style else {
      NSLog("CarPlay map: no style yet (view %@)", mapView == nil ? "not loaded" : "loaded")
      return
    }
    styleReady = false
    if CarHost.shared.styleIsJson {
      NSLog("CarPlay map: style json (%d bytes)", style.utf8.count)
      mapView.styleJSON = style
    } else if let url = URL(string: style) {
      NSLog("CarPlay map: style %@", style)
      mapView.styleURL = url
    } else {
      NSLog("CarPlay map: style is not a url: %@", style)
    }
  }

  func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
    NSLog("CarPlay map: failed to load: %@", error.localizedDescription)
  }

  func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
    NSLog("CarPlay map: style loaded, %d x %d", Int(mapView.bounds.width), Int(mapView.bounds.height))
    addLayers(style)
    for (key, image) in CarHost.shared.images { style.setImage(image, forName: key) }
    styleReady = true
    routesChanged()
    drivenChanged()
    arrowChanged()
    positionChanged()
    if let camera = pendingCamera { apply(camera) }
  }

  private func addLayers(_ style: MLNStyle) {
    let firstText = style.layers.first { $0 is MLNSymbolStyleLayer }
    func add(_ layer: MLNStyleLayer) {
      if let firstText = firstText { style.insertLayer(layer, below: firstText) } else { style.addLayer(layer) }
    }
    for id in ["routes", "driven", "arrow", "position"] {
      style.addSource(MLNShapeSource(identifier: id, shape: nil, options: nil))
    }
    func line(_ id: String, _ source: String, _ color: UIColor, _ width: Double, opacity: Double = 1)
      -> MLNLineStyleLayer
    {
      let layer = MLNLineStyleLayer(identifier: id, source: style.source(withIdentifier: source)!)
      layer.lineColor = NSExpression(forConstantValue: color)
      layer.lineWidth = NSExpression(forConstantValue: width)
      layer.lineOpacity = NSExpression(forConstantValue: opacity)
      layer.lineCap = NSExpression(forConstantValue: "round")
      layer.lineJoin = NSExpression(forConstantValue: "round")
      return layer
    }
    let alt = line("route-alt", "routes", UIColor(hex: 0x78909c), 5, opacity: 0.8)
    alt.predicate = NSPredicate(format: "chosen == NO")
    add(alt)
    let casing = line("route-casing", "routes", .white, 9)
    casing.predicate = NSPredicate(format: "chosen == YES")
    add(casing)
    let route = line("route", "routes", UIColor(hex: 0x1565c0), 6)
    route.predicate = NSPredicate(format: "chosen == YES")
    add(route)
    add(line("driven", "driven", UIColor(hex: 0x9e9e9e), 6))
    add(line("arrow-casing", "arrow", UIColor(hex: 0x0d47a1), 11))
    add(line("arrow", "arrow", .white, 6))
    let head = MLNSymbolStyleLayer(identifier: "arrow-head", source: style.source(withIdentifier: "arrow")!)
    head.iconImageName = NSExpression(forConstantValue: "arrow-head")
    head.iconScale = NSExpression(forConstantValue: 0.5)
    head.iconRotation = NSExpression(forKeyPath: "bearing")
    head.iconRotationAlignment = NSExpression(forConstantValue: "map")
    head.iconAllowsOverlap = NSExpression(forConstantValue: true)
    head.iconIgnoresPlacement = NSExpression(forConstantValue: true)
    head.predicate = NSPredicate(format: "$geometryType == 'Point'")
    style.addLayer(head)
    let puck = MLNSymbolStyleLayer(identifier: "position", source: style.source(withIdentifier: "position")!)
    puck.iconImageName = NSExpression(forConstantValue: "puck")
    puck.iconScale = NSExpression(forConstantValue: 0.5)
    puck.iconRotation = NSExpression(forKeyPath: "heading")
    puck.iconRotationAlignment = NSExpression(forConstantValue: "map")
    puck.iconAllowsOverlap = NSExpression(forConstantValue: true)
    puck.iconIgnoresPlacement = NSExpression(forConstantValue: true)
    style.addLayer(puck)
  }

  private func setGeoJson(_ id: String, _ geoJson: String?) {
    guard styleReady, let source = mapView.style?.source(withIdentifier: id) as? MLNShapeSource else { return }
    let json = geoJson ?? Self.empty
    guard let data = json.data(using: .utf8),
      let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue)
    else { return }
    source.shape = shape
  }

  // MARK: - From the host

  func imageAdded(_ key: String) {
    guard styleReady, let image = CarHost.shared.images[key] else { return }
    mapView.style?.setImage(image, forName: key)
  }

  func routesChanged() { setGeoJson("routes", CarHost.shared.routesGeoJson) }
  func drivenChanged() { setGeoJson("driven", CarHost.shared.drivenGeoJson) }
  func arrowChanged() { setGeoJson("arrow", CarHost.shared.arrowGeoJson) }

  func positionChanged() {
    guard let p = CarHost.shared.position else { return setGeoJson("position", nil) }
    let heading = p.heading ?? 0
    setGeoJson(
      "position",
      #"{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"heading":\#(heading)},"#
        + #""geometry":{"type":"Point","coordinates":[\#(p.lon),\#(p.lat)]}}]}"#)
  }

  func apply(_ camera: CarCamera) {
    guard styleReady, let mapView = mapView else {
      pendingCamera = camera
      return
    }
    pendingCamera = nil
    let center = CLLocationCoordinate2D(latitude: camera.lat, longitude: camera.lon)
    let altitude = MLNAltitudeForZoomLevel(camera.zoom, CGFloat(camera.tilt), camera.lat, mapView.frame.size)
    let target = MLNMapCamera(
      lookingAtCenter: center, altitude: altitude, pitch: CGFloat(camera.tilt), heading: camera.bearing)
    mapView.setCamera(
      target, withDuration: Double(camera.animateMs) / 1000,
      animationTimingFunction: CAMediaTimingFunction(name: .linear), completionHandler: nil)
  }

  func fit(_ bounds: CarBounds, padding: Double) {
    guard styleReady else { return }
    let box = MLNCoordinateBounds(
      sw: CLLocationCoordinate2D(latitude: bounds.south, longitude: bounds.west),
      ne: CLLocationCoordinate2D(latitude: bounds.north, longitude: bounds.east))
    let inset = CGFloat(padding / UIScreen.main.scale)
    mapView.setVisibleCoordinateBounds(
      box, edgePadding: UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset), animated: true,
      completionHandler: nil)
  }

  /// Following: the position at two thirds of the height, as on the phone.
  func applyInsets() {
    guard let mapView = mapView else { return }
    var insets = view.safeAreaInsets
    if CarHost.shared.following { insets.top += view.bounds.height * 0.35 }
    mapView.setContentInset(insets, animated: false, completionHandler: nil)
  }

  /// A pan from the template (touch or knob), in points.
  func pan(by translation: CGPoint) {
    guard let mapView = mapView else { return }
    var point = mapView.convert(mapView.centerCoordinate, toPointTo: mapView)
    point.x -= translation.x
    point.y -= translation.y
    mapView.setCenter(mapView.convert(point, toCoordinateFrom: mapView), animated: false)
  }

  func zoom(by steps: Double) {
    mapView?.setZoomLevel(mapView.zoomLevel + steps, animated: true)
  }

  func speedChanged() {
    let speed = CarHost.shared.speed
    let navigating = CarHost.shared.screen == .navigating
    showCamera(navigating ? speed : nil)
    guard navigating, let limit = speed?.limitKmh else {
      speedLimit.isHidden = true
      return
    }
    speedLimit.isHidden = false
    speedLimit.show(limit: Int(limit), matrix: speed?.limitSource == "msi")
  }

  /// The next speed camera or the average speed check you're in: above the
  /// speed limit, or in its place when there is no limit.
  private func showCamera(_ speed: CarSpeed?) {
    guard let speed = speed, let text = speed.cameraText else {
      cameraSign.isHidden = true
      return
    }
    cameraSign.show(
      icon: speed.cameraIconKey.flatMap { CarHost.shared.images[$0] }, text: text,
      detail: speed.cameraDetail, over: speed.cameraOver)
    let size = cameraSign.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    let insets = view.safeAreaInsets
    let below: CGFloat = speed.limitKmh == nil ? 0 : 56 + 6
    cameraSign.frame = CGRect(
      x: insets.left + 12, y: view.bounds.height - insets.bottom - 12 - below - size.height,
      width: size.width, height: size.height)
    cameraSign.isHidden = false
  }
}

/// The next speed camera or the average speed check you're in, as on the
/// phone (`CameraSign` in `navigation_bar.dart`): an icon and a line of text,
/// with a smaller line below; red when your average is above the limit.
final class CameraSignView: UIView {
  private let icon = UIImageView()
  private let label = UILabel()
  private let detail = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    layer.cornerRadius = 10
    label.textColor = .white
    label.font = .systemFont(ofSize: 16, weight: .bold)
    detail.textColor = UIColor.white.withAlphaComponent(0.7)
    detail.font = .systemFont(ofSize: 11)
    icon.contentMode = .scaleAspectFit
    let row = UIStackView(arrangedSubviews: [icon, label])
    row.axis = .horizontal
    row.spacing = 6
    row.alignment = .center
    let column = UIStackView(arrangedSubviews: [row, detail])
    column.axis = .vertical
    column.alignment = .center
    column.translatesAutoresizingMaskIntoConstraints = false
    addSubview(column)
    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: 20),
      icon.heightAnchor.constraint(equalToConstant: 20),
      column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      column.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
    ])
  }

  required init?(coder: NSCoder) { fatalError() }

  func show(icon image: UIImage?, text: String, detail line: String?, over: Bool) {
    icon.image = image
    label.text = text
    detail.text = line
    detail.isHidden = line == nil
    backgroundColor = over ? UIColor(hex: 0xd32f2f) : UIColor(hex: 0x263238)
  }
}

/// The speed limit as a round sign on the map, red ring when it comes from
/// the overhead signs (as on the phone).
final class SpeedLimitView: UIView {
  private let label = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .white
    layer.borderColor = UIColor.red.cgColor
    layer.borderWidth = 5
    label.textAlignment = .center
    label.textColor = .black
    label.font = .systemFont(ofSize: 20, weight: .bold)
    label.adjustsFontSizeToFitWidth = true
    addSubview(label)
  }

  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = bounds.width / 2
    label.frame = bounds.insetBy(dx: 8, dy: 8)
  }

  func show(limit: Int, matrix: Bool) {
    label.text = "\(limit)"
    layer.borderWidth = matrix ? 7 : 5
  }
}

extension UIColor {
  convenience init(hex: Int) {
    self.init(
      red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
      blue: CGFloat(hex & 0xff) / 255, alpha: 1)
  }
}
