import 'package:flutter_test/flutter_test.dart';
import 'package:otpless_headless_flutter/otpless_flutter_method_channel.dart';
import 'package:otpless_headless_flutter/otpless_flutter_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MethodChannelOtplessFlutter is a platform interface implementation',
      () {
    final MethodChannelOtplessFlutter platform = MethodChannelOtplessFlutter();
    expect(platform, isA<OtplessFlutterPlatform>());
  });
}
