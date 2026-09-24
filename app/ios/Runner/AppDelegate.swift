import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// The one Flutter engine of the app. The phone's scene and CarPlay share
  /// it, and it runs from launch: the car may connect before the phone's
  /// window exists (or without it ever appearing).
  lazy var engine: FlutterEngine = {
    let engine = FlutterEngine(name: "main")
    engine.run()
    GeneratedPluginRegistrant.register(with: engine)
    CarHost.shared.attach(engine: engine)
    return engine
  }()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    _ = engine
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
