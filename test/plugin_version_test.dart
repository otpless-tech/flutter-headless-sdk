import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otpless_headless_flutter/src/version.dart';

/// Drift guard for the wrapper-attribution token.
///
/// The token sent to the native SDKs at `initialize` embeds
/// [otplessPluginVersion] (`flutter-android-<version>` /
/// `flutter-ios-<version>`). If a release bumps `version:` in `pubspec.yaml`
/// but forgets the constant, every session would be attributed to the previous
/// plugin version — silently. This test makes that a CI failure instead.
void main() {
  test('otplessPluginVersion matches version: in pubspec.yaml', () {
    // `flutter test` runs with the package root as the working directory.
    final pubspec = File('pubspec.yaml');
    expect(pubspec.existsSync(), isTrue,
        reason: 'expected to run from the package root, cwd is '
            '${Directory.current.path}');

    final versionLines = pubspec
        .readAsLinesSync()
        // Top-level `version:` only — indented keys belong to nested maps.
        .where((line) => line.startsWith('version:'))
        .toList();

    expect(versionLines, hasLength(1),
        reason: 'pubspec.yaml should declare exactly one top-level version:');

    final pubspecVersion =
        versionLines.single.substring('version:'.length).trim();

    expect(pubspecVersion, isNotEmpty);
    expect(
      otplessPluginVersion,
      pubspecVersion,
      reason: 'lib/src/version.dart is out of sync with pubspec.yaml. '
          'Bump otplessPluginVersion to "$pubspecVersion" so the '
          'build-platform token reports the right plugin version.',
    );
  });
}
