import 'otpless_flutter_platform_interface.dart';
import 'package:otpless_headless_flutter/otpless_flutter_method_channel.dart';
import 'package:otpless_headless_flutter/models.dart';

class Otpless {
  final MethodChannelOtplessFlutter _otplessChannel =
      MethodChannelOtplessFlutter();

  Future<String?> getPlatformVersion() {
    return OtplessFlutterPlatform.instance.getPlatformVersion();
  }

  Future<bool> isWhatsAppInstalledForAndroid() async {
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

  Future<void> setDevLogging(bool isEnabled) async {
    _otplessChannel.setDevLogging(isEnabled);
  }

  Future<void> commitResponse(final dynamic response) async {
    return await _otplessChannel.commitResponse(response);
  }

  Future<bool> initTrueCaller(final OtplessTruecallerRequest? request) async {
    return await _otplessChannel.initTrueCaller(request);
  }

  Future<bool> isSdkReady() async {
    return await _otplessChannel.isSdkReady();
  }

  Future<bool> startBackground(
      OtplessResultCallback callback, OtplessAuthConfig config) async {
    return await _otplessChannel.startBackground(callback, config);
  }

  Future<bool> sendUserAuthEvent(
      AuthEvent event, bool fallback, ProviderType providerType,
      {Map<String, dynamic>? providerInfo}) async {
    return await _otplessChannel.sendUserAuthEvent(
        event, fallback, providerType,
        providerInfo: providerInfo);
  }
}
