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

  Future<bool> startBackground(
      OtplessResultCallback callback, OtplessAuthConfig config) async {
    if (!Platform.isAndroid) return false;
    return await methodChannel
        .invokeMethod("startBackground", {'arg': json.encode(config.toMap())});
  }

  Future<bool> sendUserAuthEvent(
      AuthEvent event, bool fallback, ProviderType providerType,
      {Map<String, dynamic>? providerInfo}) async {
    if (!Platform.isAndroid) return false;
    return await methodChannel.invokeMethod("userAuthEvent", {
      "event": event.name,
      "fallback": fallback,
      "providerType": providerType.name,
      if (providerInfo == null) "providerInfo": json.encode(providerInfo)
    });
  }
}
