// swift-tools-version: 5.9
// Swift Package Manager manifest for the iOS side of this plugin.
//
// Flutter discovers this at the fixed path `ios/<plugin_name>/Package.swift`
// and will NOT fall back to CocoaPods when it is missing, so an app that has
// migrated to SPM cannot use the plugin without it.
//
// `ios/otpless_headless_flutter.podspec` points at the same `Sources`
// directory, so CocoaPods and SPM build one shared source tree. Keep both
// until Flutter drops the CocoaPods path.
import PackageDescription

let package = Package(
    name: "otpless_headless_flutter",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        // Flutter requires the library product to spell the plugin name with
        // hyphens even though the package and target keep the underscores.
        .library(
            name: "otpless-headless-flutter",
            targets: ["otpless_headless_flutter"]
        ),
    ],
    dependencies: [
        // The Flutter framework itself. Flutter symlinks this plugin into its
        // generated `.packages` directory next to a `FlutterFramework`
        // package, which is what makes the relative path resolve; the path is
        // only valid inside a Flutter build, not a bare `swift build`.
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Mirrors the podspec's exact pin on `OtplessBM/Core`. SPM has no
        // subspecs: upstream exposes the whole module as one `OtplessBM`
        // product, so there is nothing narrower to depend on here.
        .package(
            url: "https://github.com/otpless-tech/otpless-headless-iOS-sdk.git",
            exact: "3.0.1"
        ),
    ],
    targets: [
        .target(
            name: "otpless_headless_flutter",
            dependencies: [
                .product(
                    name: "FlutterFramework",
                    package: "FlutterFramework"
                ),
                .product(
                    name: "OtplessBM",
                    package: "otpless-headless-iOS-sdk"
                ),
            ]
        ),
    ]
)
