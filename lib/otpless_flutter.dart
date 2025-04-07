import 'otpless_flutter_platform_interface.dart';
import 'package:otpless_headless_flutter/otpless_flutter_method_channel.dart';

class Otpless {
  final MethodChannelOtplessFlutter _otplessChannel =
      MethodChannelOtplessFlutter();

  Future<String?> getPlatformVersion() {
    return OtplessFlutterPlatform.instance.getPlatformVersion();
  }

  Future<bool> isWhatsAppInstalled() async {
    return _otplessChannel.isWhatsAppInstalled();
  }

  /*
    start headless
  */
  Future<void> start(
      OtplessResultCallback callback, Map<String, dynamic> jsonObject) async {
    _otplessChannel.start(callback, jsonObject);
  }

  Future<void> initialize(String appid, {double timeout = 30.0}) async {
    _otplessChannel.initialize(appid, timeout);
  }

  Future<void> setResponseCallback(OtplessResultCallback callback) async {
    _otplessChannel.setResponseCallback(callback);
  }

  Future<void> enableDebugLogging(bool isDebugLoggingEnabled) async {
    _otplessChannel.enableDebugLogging(isDebugLoggingEnabled);
  }

  Future<void> commitResponse(final dynamic response) async {
    return await _otplessChannel.commitResponse(response);
  }
}
