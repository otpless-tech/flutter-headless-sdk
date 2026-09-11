import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otpless_headless_flutter/otpless_flutter.dart';
import 'package:otpless_headless_flutter/otpless_flutter_method_channel.dart';
import 'package:otpless_headless_flutter/otpless_flutter_platform_interface.dart';
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

    test('default: pinning disabled, no loginUri, no timeout', () async {
      await Otpless().initialize('APP_ID');

      expect(log, hasLength(1));
      expect(log.single.method, 'initialize');
      expect(log.single.arguments, <String, dynamic>{
        'appId': 'APP_ID',
        'loginUri': null,
        'sslPinning': 'disabled',
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
      });
    });

    test('sslPinning: disabled marshals as "disabled"', () async {
      await Otpless()
          .initialize('APP_ID', sslPinning: OtplessSslPinning.disabled);

      expect(log.single.arguments, <String, dynamic>{
        'appId': 'APP_ID',
        'loginUri': null,
        'sslPinning': 'disabled',
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
      });
    });

    test('deprecated timeout is accepted but never marshalled', () async {
      // ignore: deprecated_member_use_from_same_package
      await Otpless().initialize('APP_ID', timeout: 5);

      expect(log.single.arguments, isNot(contains('timeout')));
      expect(log.single.arguments, <String, dynamic>{
        'appId': 'APP_ID',
        'loginUri': null,
        'sslPinning': 'disabled',
      });
    });

    test('OtplessSslPinning is exported from otpless_flutter.dart', () {
      // Compile-time check: the enum resolves via the main library import.
      expect(OtplessSslPinning.values,
          [OtplessSslPinning.disabled, OtplessSslPinning.enabled]);
    });
  });
}
