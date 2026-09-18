import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otpless_headless_flutter/otpless_flutter.dart';
import 'package:otpless_headless_flutter/otpless_flutter_method_channel.dart';
import 'package:otpless_headless_flutter/otpless_flutter_platform_interface.dart';
import 'package:otpless_headless_flutter/src/version.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockOtplessFlutterPlatform
    with MockPlatformInterfaceMixin
    implements OtplessFlutterPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<void> initialize(
    String appId, {
    OtplessSslPinning sslPinning = OtplessSslPinning.disabled,
    String? loginUri,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final OtplessFlutterPlatform initialPlatform =
      OtplessFlutterPlatform.instance;

  test('$MethodChannelOtplessFlutter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelOtplessFlutter>());
  });

  test('getPlatformVersion', () async {
    Otpless otplessHeadlessPlugin = Otpless();
    MockOtplessFlutterPlatform fakePlatform = MockOtplessFlutterPlatform();
    OtplessFlutterPlatform.instance = fakePlatform;

    expect(await otplessHeadlessPlugin.getPlatformVersion(), '42');
  });

  group('initialize method-channel payload', () {
    const channel = MethodChannel('otpless_headless_flutter');
    final List<MethodCall> log = <MethodCall>[];

    // NOT the on-device value. `flutter test` runs on the host VM, where both
    // Platform.isAndroid and Platform.isIOS are false, so initialize sends the
    // defensive bare form. On a real device the token is
    // 'flutter-android-<version>' / 'flutter-ios-<version>'.
    const String hostBuildPlatform = 'flutter-$otplessPluginVersion';

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        log.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('default: pinning disabled, loginUri null', () async {
      await Otpless().initialize('APP_ID');

      expect(log, hasLength(1));
      expect(log.single.method, 'initialize');
      expect(log.single.arguments, <String, dynamic>{
        'appId': 'APP_ID',
        'loginUri': null,
        'sslPinning': 'disabled',
        'buildPlatform': hostBuildPlatform,
      });
    });

    test('sslPinning: enabled marshals as "enabled"', () async {
      await Otpless()
          .initialize('APP_ID', sslPinning: OtplessSslPinning.enabled);

      expect(log.single.method, 'initialize');
      expect(log.single.arguments, <String, dynamic>{
        'appId': 'APP_ID',
        'loginUri': null,
        'sslPinning': 'enabled',
        'buildPlatform': hostBuildPlatform,
      });
    });

    test('sslPinning: disabled marshals as "disabled"', () async {
      await Otpless()
          .initialize('APP_ID', sslPinning: OtplessSslPinning.disabled);

      expect(log.single.arguments, <String, dynamic>{
        'appId': 'APP_ID',
        'loginUri': null,
        'sslPinning': 'disabled',
        'buildPlatform': hostBuildPlatform,
      });
    });

    test('loginUri is passed through', () async {
      await Otpless().initialize(
        'APP_ID',
        loginUri: 'myapp://otpless',
        sslPinning: OtplessSslPinning.enabled,
      );

      expect(log.single.arguments, <String, dynamic>{
        'appId': 'APP_ID',
        'loginUri': 'myapp://otpless',
        'sslPinning': 'enabled',
        'buildPlatform': hostBuildPlatform,
      });
    });

    test('OtplessSslPinning is exported from otpless_flutter.dart', () {
      // Compile-time check: the enum resolves via the main library import.
      expect(OtplessSslPinning.values,
          [OtplessSslPinning.disabled, OtplessSslPinning.enabled]);
    });

    group('buildPlatform token shape', () {
      test('is always sent under the buildPlatform key', () async {
        await Otpless().initialize('APP_ID');

        final arguments = log.single.arguments as Map;
        expect(arguments.containsKey('buildPlatform'), isTrue);
        expect(arguments['buildPlatform'], isA<String>());
      });

      test('starts with "flutter-" and ends with the plugin version', () async {
        await Otpless().initialize('APP_ID');

        final token = (log.single.arguments as Map)['buildPlatform'] as String;
        expect(token, startsWith('flutter-'));
        expect(token, endsWith(otplessPluginVersion));
        expect(token, isNot(equals('flutter')),
            reason: 'the bare legacy token must no longer be sent');
      });

      test('on the host VM it is the defensive bare form (not a device token)',
          () async {
        await Otpless().initialize('APP_ID');

        final token = (log.single.arguments as Map)['buildPlatform'] as String;
        // Host-only expectation: flutter test is neither Android nor iOS.
        expect(token, 'flutter-$otplessPluginVersion');
      });
    });
  });
}
