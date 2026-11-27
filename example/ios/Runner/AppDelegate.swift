import UIKit
import Flutter
import OtplessBM

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Extra engines spawned from the debug button; held so they stay alive.
  private var secondaryEngines: [FlutterEngine] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    print("[OtplessExample] AppDelegate.application(didFinishLaunchingWithOptions:) — AppDelegate is wired in")
    GeneratedPluginRegistrant.register(with: self)
    setUpDebugChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

    override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("[OtplessExample] AppDelegate.application(open:) url=\(url)")
        super.application(app, open: url, options: options)
        if Otpless.shared.isOtplessDeeplink(url: url){
            Task {
                await Otpless.shared.handleDeeplink(url)
            }

        }
        return true
    }

  // Reproduces the multi-engine setup (e.g. BigBasket): a second engine
  // registers every plugin, including OTPLESS, but its Dart side never sets
  // the OTPLESS callback handler. Responses must still reach the main engine.
  private func setUpDebugChannel() {
    guard let registrar = self.registrar(forPlugin: "OtplessExampleDebug") else { return }
    let channel = FlutterMethodChannel(name: "otpless_example/debug", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "spawnSecondaryEngine":
        let engine = FlutterEngine(name: "secondary-\(self.secondaryEngines.count + 1)", project: nil, allowHeadlessExecution: true)
        engine.run(withEntrypoint: "secondaryEngineMain")
        GeneratedPluginRegistrant.register(with: engine)
        self.secondaryEngines.append(engine)
        print("[OtplessExample] spawned secondary engine #\(self.secondaryEngines.count)")
        result(self.secondaryEngines.count)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

}
