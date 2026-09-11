import 'otpless_flutter_platform_interface.dart';
import 'package:otpless_headless_flutter/otpless_flutter_method_channel.dart';
import 'package:otpless_headless_flutter/models.dart';

export 'package:otpless_headless_flutter/models.dart' show OtplessSslPinning;

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

  /// Initialises the native OTPLESS SDK for [appId].
  ///
  /// [sslPinning] opts in to SSL certificate pinning of the OTPLESS backend on
  /// both Android and iOS. It defaults to [OtplessSslPinning.disabled], so
  /// existing integrations see no behaviour change. With pinning enabled, a
  /// failed pin check surfaces as `responseType: "FAILED"`, `statusCode: 5004`
  /// in the response callback and no auth request is sent.
  ///
  /// [loginUri] is the deep-link URI the native SDK returns to after OAuth
  /// channels. When omitted the SDK derives `otpless.<appid>://otpless`.
  ///
  /// [timeout] is deprecated: neither native SDK ever read it and it is no
  /// longer sent across the method channel.
  Future<void> initialize(
    String appId, {
    OtplessSslPinning sslPinning = OtplessSslPinning.disabled,
    String? loginUri,
    @Deprecated('timeout was never applied natively and will be removed')
    double timeout = 30.0,
  }) async {
    await _otplessChannel.initialize(
      appId,
      sslPinning: sslPinning,
      loginUri: loginUri,
    );
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

  Future<bool> startOnetap(
      OtplessResultCallback callback, OtplessAuthConfig config) async {
    return await _otplessChannel.startOnetap(callback, config);
  }

  Future<void> startInBackground(
      OtplessResultCallback callback, Map<String, dynamic> jsonObject) async {
    return _otplessChannel.startInBackground(callback, jsonObject);
  }

  Future<bool> sendUserAuthEvent(
      AuthEvent event, bool fallback, ProviderType providerType,
      {Map<String, dynamic>? providerInfo}) async {
    return await _otplessChannel.sendUserAuthEvent(
        event, fallback, providerType,
        providerInfo: providerInfo);
  }

  Future<void> setMfaEnabled(bool enabled) async {
    return _otplessChannel.setMfaEnabled(enabled);
  }

  Future<void> initSession(String appId) async {
    return _otplessChannel.initSession(appId);
  }

  Future<Map<String, dynamic>> getActiveSession() async {
    return _otplessChannel.getActiveSession();
  }

  Future<void> logoutSession() async {
    return _otplessChannel.logoutSession();
  }

  Future<void> closeDialogIfOpen() async {
    return _otplessChannel.closeDialogIfOpen();
  }

  Future<bool> checkSimBindingStatus() async {
    return _otplessChannel.checkSimBindingStatus();
  }

  Future<void> clearSimBinding() async {
    return _otplessChannel.clearSimBinding();
  }

  Future<void> setSimBindingEnabled(bool enabled) async {
    return _otplessChannel.setSimBindingEnabled(enabled);
  }
}
