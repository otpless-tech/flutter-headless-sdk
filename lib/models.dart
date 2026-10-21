enum OTFooterType {
  footerTypeSkip,
  footerTypeAnotherMobileNo,
  footerTypeAnotherMethod,
  footerTypeManually,
  footerTypeLater,
}

enum OTButtonShape {
  buttonShapeRounded,
  buttonShapeRectangle,
}

enum OTVerifyOption {
  optionVerifyOnlyTcUsers,
  optionVerifyAllUsers,
}

enum OTHeadingConsent {
  sdkConsentHeadingLogInTo,
  sdkConsentHeadingSignUpWith,
  sdkConsentHeadingSignInTo,
  sdkConsentHeadingVerifyNumberWith,
  sdkConsentHeadingRegisterWith,
  sdkConsentHeadingGetStartedWith,
  sdkConsentHeadingProceedWith,
  sdkConsentHeadingVerifyWith,
  sdkConsentHeadingVerifyProfileWith,
  sdkConsentHeadingVerifyYourProfileWith,
  sdkConsentHeadingVerifyPhoneNoWith,
  sdkConsentHeadingVerifyYourNoWith,
  sdkConsentHeadingContinueWith,
  sdkConsentHeadingCompleteOrderWith,
  sdkConsentHeadingPlaceOrderWith,
  sdkConsentHeadingCompleteBookingWith,
  sdkConsentHeadingCheckoutWith,
  sdkConsentHeadingManageDetailsWith,
  sdkConsentHeadingManageYourDetailsWith,
  sdkConsentHeadingLoginToWithOneTap,
  sdkConsentHeadingSubscribeTo,
  sdkConsentHeadingGetUpdatesFrom,
  sdkConsentHeadingContinueReadingOn,
  sdkConsentHeadingGetNewUpdatesFrom,
  sdkConsentHeadingLoginSignupWith,
}

enum OTLoginPrefixText {
  loginTextPrefixToGetStarted,
  loginTextPrefixToContinue,
  loginTextPrefixToPlaceOrder,
  loginTextPrefixToCompleteYourPurchase,
  loginTextPrefixToCheckout,
  loginTextPrefixToCompleteYourBooking,
  loginTextPrefixToProceedWithYourBooking,
  loginTextPrefixToContinueWithYourBooking,
  loginTextPrefixToGetDetails,
  loginTextPrefixToViewMore,
  loginTextPrefixToContinueReading,
  loginTextPrefixToProceed,
  loginTextPrefixForNewUpdates,
  loginTextPrefixToGetUpdates,
  loginTextPrefixToSubscribe,
  loginTextPrefixToSubscribeAndGetUpdates,
}

enum OTCtaText {
  ctaTextProceed,
  ctaTextContinue,
  ctaTextAccept,
  ctaTextConfirm,
}

class OtplessTruecallerConfig {
  final OTFooterType? footerType;
  final OTButtonShape? shape;
  final OTVerifyOption? verifyOption;
  final OTHeadingConsent? heading;
  final OTLoginPrefixText? loginPrefixText;
  final OTCtaText? ctaText;
  final String?
      locale; // Dart doesn't have java.util.Locale; use a locale string like "en-US"
  final String? buttonColor;
  final String? buttonTextColor;

  const OtplessTruecallerConfig({
    this.footerType,
    this.shape,
    this.verifyOption,
    this.heading,
    this.loginPrefixText,
    this.ctaText,
    this.locale,
    this.buttonColor,
    this.buttonTextColor,
  });

  Map<String, dynamic> toMap() {
    return {
      'footerType': footerType?.name,
      'shape': shape?.name,
      'verifyOption': verifyOption?.name,
      'heading': heading?.name,
      'loginPrefixText': loginPrefixText?.name,
      'ctaText': ctaText?.name,
      'locale': locale,
      'buttonColor': buttonColor,
      'buttonTextColor': buttonTextColor,
    };
  }
}

enum OTScope { profile, phone, openId, offlineAccess, email, address }

class OtplessTruecallerRequest {
  final OtplessTruecallerConfig? config;
  final List<OTScope> scopes;

  const OtplessTruecallerRequest({
    this.config,
    this.scopes = const [OTScope.openId, OTScope.phone, OTScope.profile],
  });

  Map<String, dynamic> toMap() {
    return {
      'config': config?.toMap(),
      'scopes': scopes.map((e) => e.name).toList(),
    };
  }
}

class OtplessAuthConfig {
  final bool isForeground;
  final String? otp;
  final String? tid;
  final DeviceFingerprintMode deviceFingerprintMode;

  const OtplessAuthConfig(
    this.isForeground, {
    this.otp,
    this.tid,
    this.deviceFingerprintMode = DeviceFingerprintMode.none,
  });

  Map<String, dynamic> toMap() {
    return {
      'isForeground': isForeground,
      if (otp != null) 'otp': otp,
      if (tid != null) 'tid': tid,
      'deviceFingerprintMode': deviceFingerprintMode.name,
    };
  }
}

enum AuthEvent { authInitiated, authSuccess, authFailed }

enum ProviderType { client, otpless }

enum DeviceFingerprintMode { none, async, sync }

/// SSL certificate pinning mode, passed to [Otpless.initialize].
///
/// Defaults to [disabled], which matches the pre-3.0 behaviour. When [enabled] and pin validation fails, the SDK fails
/// closed and delivers `responseType: "FAILED"`, `statusCode: 5004` with
/// `response: {"errorCode": "5004", "errorMessage": "SSL pin validation failed"}`
/// on both platforms; no authentication request leaves the device.
///
/// Marshalled to the native side as the string `"enabled"` / `"disabled"`;
/// unknown values are treated as disabled.
enum OtplessSslPinning { disabled, enabled }

/// Keys accepted by the `config` map of [Otpless.initialize]. Mirrors the
/// native Android `OtplessConfigKey`.
///
/// - [disableOtpAutoRead]: set to `"true"` to stop the SDK from registering
///   the SMS / WhatsApp zero-tap OTP auto-read receivers (intended for
///   SNA-only integrations). Auto-read stays on when the key is absent or its
///   value is anything other than exactly `"true"`. Android only; iOS has no
///   OTP auto-read and ignores it.
///
/// Values apply per `initialize` call: call `initialize` again to change them.
/// Marshalled to the native side by enum name; unknown keys are ignored.
enum OtplessConfigKey { disableOtpAutoRead }

/// SIM binding state reported by the Android SIM binding monitor. See
/// `Otpless.setSimBindingMonitorCallback`.
///
/// * [enabled] — a SIM binding was saved for this device.
/// * [disabled] — the binding was cleared (via `clearSimBinding`, or because
///   saving it failed), or the bound SIM was removed while monitoring.
enum SimBindingState { enabled, disabled }
