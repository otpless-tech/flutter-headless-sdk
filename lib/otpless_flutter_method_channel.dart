import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otpless_headless_flutter/models.dart';

import 'otpless_flutter_platform_interface.dart';
import 'src/version.dart';

typedef OtplessResultCallback = void Function(dynamic);
typedef OtplessSimEventListener = void Function(List<Map<String, dynamic>>);

/// Wrapper-attribution token sent to the native SDKs at `initialize`.
///
/// Computed here, in Dart, so [otplessPluginVersion] is the single source of
/// truth: the Kotlin and Swift bridges only forward whatever arrives over the
/// method channel, instead of each hardcoding a version that would drift on
/// every release.
///
/// Emitted by the native device-telemetry event as:
/// * Android — `otpless-headless-sdk(flutter-android-<pluginVersion>)`
/// * iOS — `otpless-headless(flutter-ios-<pluginVersion>)`
///
/// The plugin only supports Android and iOS; the bare `flutter-<version>` form
/// is a defensive fallback that also shows up under `flutter test`, which runs
/// on the host where both [Platform.isAndroid] and [Platform.isIOS] are false.
String _buildPlatformToken() {
  if (Platform.isAndroid) return 'flutter-android-$otplessPluginVersion';
  if (Platform.isIOS) return 'flutter-ios-$otplessPluginVersion';
  return 'flutter-$otplessPluginVersion';
}

/// An implementation of [OtplessFlutterPlatform] that uses method channels.
class MethodChannelOtplessFlutter extends OtplessFlutterPlatform {
  final eventChannel = const EventChannel('otpless_callback_event');

  @visibleForTesting
  final methodChannel = const MethodChannel('otpless_headless_flutter');

  OtplessResultCallback? _callback;

  MethodChannelOtplessFlutter() {
    _setEventChannel();
  }

  void _setEventChannel() {
    methodChannel.setMethodCallHandler((call) async {
      if (call.method == "otpless_callback_event") {
        final json = call.arguments as String;
        final result = jsonDecode(json);
        // setResponseCallback is expected before initialize; the null-safe call
        // is just a guard so a stray event can never throw.
        _callback?.call(result);
      }
    });
  }

  Future<bool> isWhatsAppInstalled() async {
    if (!Platform.isAndroid) {
      return false;
    }
    final isInstalled = await methodChannel.invokeMethod("isWhatsAppInstalled");
    return isInstalled as bool;
  }

  Future<void> start(
      OtplessResultCallback callback, Map<String, dynamic> jsonObject) async {
    _callback = callback;
    await methodChannel.invokeMethod("start", {'arg': json.encode(jsonObject)});
  }

  @override
  Future<void> initialize(
    String appId, {
    OtplessSslPinning sslPinning = OtplessSslPinning.disabled,
    String? loginUri,
  }) async {
    await methodChannel.invokeMethod("initialize", {
      'appId': appId,
      'loginUri': loginUri,
      'sslPinning': sslPinning.name,
      // Internal channel key, not merchant-facing API: there is no Dart
      // parameter for this. See [_buildPlatformToken].
      'buildPlatform': _buildPlatformToken(),
    });
  }

  Future<void> setResponseCallback(OtplessResultCallback callback) async {
    _callback = callback;
    await methodChannel.invokeMethod("setResponseCallback");
  }

  Future<void> setDevLogging(bool isEnabled) async {
    await methodChannel.invokeMethod("setDevLogging", {'isEnabled': isEnabled});
  }

  Future<void> commitResponse(final dynamic response) async {
    await methodChannel.invokeMethod("commitResponse", {"response": response});
  }

  Future<bool> initTrueCaller(final OtplessTruecallerRequest? request) async {
    if (!Platform.isAndroid) {
      return false;
    }
    if (request != null) {
      return await methodChannel
          .invokeMethod("initTrueCaller", {"request": request.toMap()});
    } else {
      return await methodChannel.invokeMethod("initTrueCaller");
    }
  }

  Future<bool> isSdkReady() async {
    return await methodChannel.invokeMethod("isSdkReady");
  }

  Future<bool> startOnetap(
      OtplessResultCallback callback, OtplessAuthConfig config) async {
    _callback = callback;
    final res = await methodChannel
        .invokeMethod("startOnetap", {'arg': json.encode(config.toMap())});
    return (res as bool?) ?? false;
  }

  Future<void> startInBackground(
      OtplessResultCallback callback, Map<String, dynamic> jsonObject) async {
    if (!Platform.isAndroid) return;
    _callback = callback;
    await methodChannel
        .invokeMethod("startInBackground", {'arg': json.encode(jsonObject)});
  }

  Future<bool> sendUserAuthEvent(
      AuthEvent event, bool fallback, ProviderType providerType,
      {Map<String, dynamic>? providerInfo}) async {
    final res = await methodChannel.invokeMethod("userAuthEvent", {
      "event": event.name,
      "fallback": fallback,
      "providerType": providerType.name,
      if (providerInfo != null) "providerInfo": json.encode(providerInfo),
    });
    return (res as bool?) ?? false;
  }

  Future<void> setMfaEnabled(bool enabled) async {
    await methodChannel.invokeMethod("setMfaEnabled", {'enabled': enabled});
  }

  Future<void> initSession(String appId) async {
    await methodChannel.invokeMethod("initSession", {'appId': appId});
  }

  Future<Map<String, dynamic>> getActiveSession() async {
    final raw = await methodChannel.invokeMethod("getActiveSession");
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {'isActive': false};
  }

  Future<void> logoutSession() async {
    await methodChannel.invokeMethod("logoutSession");
  }

  Future<void> closeDialogIfOpen() async {
    if (!Platform.isAndroid) return;
    await methodChannel.invokeMethod("closeDialogIfOpen");
  }

  Future<bool> checkSimBindingStatus() async {
    if (!Platform.isAndroid) return false;
    final res = await methodChannel.invokeMethod("checkSimBindingStatus");
    return (res as bool?) ?? false;
  }

  Future<void> clearSimBinding() async {
    if (!Platform.isAndroid) return;
    await methodChannel.invokeMethod("clearSimBinding");
  }

  Future<void> setSimBindingEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    await methodChannel
        .invokeMethod("setSimBindingEnabled", {'enabled': enabled});
  }
}
