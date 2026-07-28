import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otpless_headless_flutter/models.dart';

import 'otpless_flutter_platform_interface.dart';

typedef OtplessResultCallback = void Function(dynamic);
typedef OtplessSimEventListener = void Function(List<Map<String, dynamic>>);

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
        _callback!(result);
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

  Future<void> initialize(String appid, double timeout) async {
    await methodChannel
        .invokeMethod("initialize", {'appId': appid, 'timeout': timeout});
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
