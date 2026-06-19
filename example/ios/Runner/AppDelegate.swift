import UIKit
import Flutter
import OtplessBM

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    print("[OtplessExample] AppDelegate.application(didFinishLaunchingWithOptions:) — AppDelegate is wired in")
    GeneratedPluginRegistrant.register(with: self)
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

}
