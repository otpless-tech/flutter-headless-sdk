/// This plugin's own version, kept in lock-step with `version:` in
/// `pubspec.yaml`.
///
/// Internal only: this file lives under `lib/src/` and is deliberately **not**
/// exported from `otpless_flutter.dart`, so it never becomes merchant-facing
/// API. It exists so the wrapper-attribution token sent to the native SDKs at
/// `initialize` (`flutter-android-<version>` / `flutter-ios-<version>`) has a
/// single source of truth in Dart instead of being duplicated in Kotlin and
/// Swift, where it would silently drift on every release.
///
/// `test/plugin_version_test.dart` parses `pubspec.yaml` and fails if this
/// constant falls out of sync, so a forgotten bump breaks CI rather than
/// shipping a wrong token.
const String otplessPluginVersion = '3.0.1';
