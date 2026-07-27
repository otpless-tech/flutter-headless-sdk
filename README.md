
<p align="center">
  <img src="https://github.com/otpless-tech/Otpless-iOS-SDK/blob/main/otpless.svg" height="80"/>
</p>

# OTPLESS Flutter Headless SDK

The new Headless Authentication SDK offers faster performance, greater reliability, and enhanced security. For a smoother authentication and integration experience, we strongly recommend migrating by removing the old SDK and following the steps below.


# Install OTPLESS SDK Dependency
[![pub package](https://img.shields.io/pub/v/otpless_headless_flutter.svg)](https://pub.dartlang.org/packages/otpless_headless_flutter)


# Installation

```xml
dependencies: otpless_headless_flutter: ^<latest_version>
```

```dart
flutter pub get
```

## Toolchain requirements (2.0.0+)

The underlying native SDKs (`otpless-headless-sdk 0.9.0`, `OtplessBM/Core 2.3.2`) pull in transitive dependencies that require newer toolchains than the pre-2.0 releases needed:

- **Android**: Android Gradle Plugin **8.9.1+** and `compileSdkVersion` **36+**. The 0.9.0 Android SDK transitively depends on `androidx.core:core:1.18.0`, which enforces this minimum. Update `android/settings.gradle` and `android/app/build.gradle` in your consuming app accordingly.
- **iOS**: deployment target **13.0+** (unchanged). CocoaPods with `OtplessBM/Core 2.3.2` on the trunk. If you use `OtplessChannelType.GOOGLE_SDK` or `FACEBOOK_SDK`, add the matching subspec (`OtplessBM/GoogleSupport`, `OtplessBM/FacebookSupport`) to your `ios/Podfile`.

## Platform support matrix

| Dart method | Android | iOS |
|---|:---:|:---:|
| `initialize` | ✅ | ✅ |
| `setResponseCallback` | ✅ | ✅ |
| `setDevLogging` | ✅ | ✅ |
| `start` | ✅ | ✅ |
| `startOnetap` (OneTap discovery) — renamed from `startBackground` | ✅ | ✅ *(new in 2.0)* |
| `commitResponse` | ✅ | ✅ |
| `isSdkReady` | ✅ | ✅ |
| `sendUserAuthEvent` | ✅ | ✅ *(new in 2.0)* |
| `setDeviceFingerprintMode` | ✅ | ✅ |
| `setMfaEnabled` | ✅ | ✅ |
| `initSession` / `getActiveSession` / `logoutSession` | ✅ | ✅ |
| `startInBackground` (silent regular auth) | ✅ | ❌ (no SDK equivalent) |
| `isWhatsAppInstalledForAndroid` | ✅ | ❌ returns `false` |
| `initTrueCaller` | ✅ | ❌ returns `false` (no iOS Truecaller SDK) |
| `checkSimBindingStatus` / `clearSimBinding` / `setSimBindingEnabled` | ✅ | ❌ (no SDK equivalent) |
| `closeDialogIfOpen` | ✅ | ❌ (no SDK equivalent) |
| Deep-link handling / Passkey / Facebook SDK register | via manifest / no-op | client wires up in `AppDelegate` / `SceneDelegate` (see below) |

# Initialize the SDK

## Import 

```dart
import 'package:otpless_headless_flutter/otpless_flutter.dart';
```

```dart
final _otplessHeadlessPlugin = Otpless();
```

```dart
@override
void initState() {
  super.initState();
  _otplessHeadlessPlugin.initialize("YOUR_APP_ID");
  _otplessHeadlessPlugin.setResponseCallback(onOtplessResponse);
}
```

# Initiate Authentication
## Phone Auth

### Request
```dart
void startWithPhone(String phoneNumber) {
    final Map<String, dynamic> args = {
        "phone": "phoneNumber",
        "countryCode": "countryCode",
    };
    _otplessHeadlessPlugin.start(onOtplessResponse, args);
}
```

### Verify

```dart
void verifyPhoneOtp(String phoneNumber, String otp) {
    final Map<String, dynamic> args = {
        "phone": "phoneNumber",
        "countryCode": "countryCode",
        "otp": "otp",
    };
    _otplessHeadlessPlugin.start(onOtplessResponse, args);
}
```

# Response Handling

```dart
void onOtplessResponse(dynamic result) {
  _otplessHeadlessPlugin.commitResponse(result);

  final responseType = result['responseType'];

  switch (responseType) {
    case "SDK_READY":
      debugPrint("SDK is ready");
      break;

    case "FAILED":
      debugPrint("SDK initialization failed");
      // Handle SDK initialization failure
      break;

    case "INITIATE":
      if (result["statusCode"] == 200) {
        debugPrint("Headless authentication initiated");
        final authType = result["response"]["authType"]; // This is the authentication type
        if (authType == "OTP") {
         // Take user to OTP verification screen
        } else if (authType == "SILENT_AUTH") {
          // Handle Silent Authentication initiation by showing 
          // loading status for SNA flow.
        }
      } else {
        // Handle initiation error. 
        // To handle initiation error response, please refer to the error handling section.
        if (Platform.isAndroid) {
          handleInitiateErrorAndroid(result["response"]);
        } else if (Platform.isIOS) {  
          handleInitiateErrorIOS(result["response"]);
        }
      }
      break;

    case "OTP_AUTO_READ":
      // OTP_AUTO_READ is triggered only in ANDROID devices for WhatsApp and SMS.
        final otp = result["response"]["otp"];
        debugPrint("OTP Received: $otp");
      break;

    case "VERIFY":
      final authType = result["response"]["authType"];
      if (authType == "SILENT_AUTH") {
        if (result["statusCode"] == 9106) {
            // Silent Authentication and all fallback authentication methods in SmartAuth have failed.
            //  The transaction cannot proceed further. 
            // Handle the scenario to gracefully exit the authentication flow 
        } else {
            // Silent Authentication failed. 
            // If SmartAuth is enabled, the INITIATE response 
            // will include the next available authentication method configured in the dashboard.
        }
      } else {
        // To handle verification failed response, please refer to the error handling section.
        if (Platform.isAndroid) {
          handleVerifyErrorAndroid(result["response"]);
        } else if (Platform.isIOS) {  
          handleVerifyErrorIOS(result["response"]);
        }
      }
      break;

    case "DELIVERY_STATUS":
        // This function is called when delivery is successful for your authType.
        final authType = result["response"]["authType"];
        // It is the authentication type (OTP, MAGICLINK, OTP_LINK) for which the delivery status is being sent
        final deliveryChannel = result["response"]["deliveryChannel"];
        // It is the delivery channel (SMS, WHATSAPP, etc) on which the authType has been delivered
        break;

    case "ONETAP":
      final token = result["response"]["token"];
      if (token != null) {
        debugPrint("OneTap Data: $token");
        // Process token and proceed
      }
      break;

    case "FALLBACK_TRIGGERED":
        // A fallback occurs when an OTP delivery attempt on one channel fails,  
        // and the system automatically retries via the subsequent channel selected on Otpless Dashboard.  
        // For example, if a merchant opts for SmartAuth with primary channal as WhatsApp and secondary channel as SMS,
        // in that case, if OTP delivery on WhatsApp fails, the system will automatically retry via SMS.
        // The response will contain the deliveryChannel to which the OTP has been sent.
        final newDeliveryChannel = result["response"]["deliveryChannel"];
        if (newDeliveryChannel != null) {
            // This is the deliveryChannel to which the OTP has been sent
        }
      break;

    default:
      debugPrint("Unknown response type: $responseType");
      break;
  }

}
```


# Android manifest update
Add Network Security Config inside your android/app/src/main/AndroidManifest.xml file into your <application> code block (Only required if you are using the SNA feature):

```xml
android:networkSecurityConfig="@xml/otpless_network_security_config"
```
<br>

# Ios info.plist update

Add the following block to your ios/Runner/info.plist file (Only required if you are using the SNA feature):

```xml
<dict>
	<key>NSAllowsArbitraryLoads</key>
	<true/>
	<key>NSExceptionDomains</key>
	<dict>
		<key>80.in.safr.sekuramobile.com</key>
		<dict>
			<key>NSIncludesSubdomains</key>
			<true/>
			<key>NSTemporaryExceptionAllowsInsecureHTTPLoads</key>
			<true/>
			<key>NSTemporaryExceptionMinimumTLSVersion</key>
			<string>TLSv1.1</string>
		</dict>
		<key>partnerapi.jio.com</key>
		<dict>
			<key>NSIncludesSubdomains</key>
			<true/>
			<key>NSTemporaryExceptionAllowsInsecureHTTPLoads</key>
			<true/>
			<key>NSTemporaryExceptionMinimumTLSVersion</key>
			<string>TLSv1.1</string>
		</dict>
	</dict>
</dict>
```

</br>
</br>

# iOS AppDelegate / SceneDelegate integration

The plugin does not wrap iOS URL handlers, Facebook SDK registration, or WebAuthn. If your merchant flow requires them, add the following in your host iOS app.

## Deep-link callback (required for OAuth channel types like `GMAIL`, `TWITTER`, etc.)

In `ios/Runner/AppDelegate.swift`:

```swift
import OtplessBM

override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if Otpless.shared.isOtplessDeeplink(url: url) {
        Task { await Otpless.shared.handleDeeplink(url) }
        return true
    }
    return super.application(app, open: url, options: options)
}
```

For SceneDelegate apps, add to `SceneDelegate.swift`:

```swift
func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts where Otpless.shared.isOtplessDeeplink(url: context.url) {
        Task { await Otpless.shared.handleDeeplink(context.url) }
    }
}
```

## Facebook SDK (only if using `FACEBOOK_SDK` channel)

Add `OtplessBM/FacebookSupport` subspec to `ios/Podfile`. Then wire it up in `AppDelegate.swift`:

```swift
override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    Otpless.shared.registerFBApp(application, didFinishLaunchingWithOptions: launchOptions)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
}

override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    Otpless.shared.registerFBApp(app, open: url, options: options)
    return super.application(app, open: url, options: options)
}
```

## Passkey / WebAuthn

`Otpless.shared.authorizeViaPasskey(withRequest:windowScene:)` is not exposed through this Flutter plugin. If your flow needs it, call it from Swift with a resolved `UIWindowScene`.


# Migration from 1.x to 2.0

## Breaking changes

- **`startBackground(callback, config)` is renamed to `startOnetap(callback, config)`.** The old name implied a background OTP flow, but the method actually presents the OneTap / verified-contact sheet. Replace every call site.
- **iOS parity for `startOnetap` and `sendUserAuthEvent`.** These now execute on both platforms instead of silently returning `false` on iOS. If your app relied on iOS being a no-op, add a `Platform.isAndroid` guard on your side.
- **New `responseType` values** may arrive in the callback: `AUTH_TERMINATED`, `MFA_FACTOR_COMPLETED`, `AUTO_FLOW_ACTION` (Android only). Callers that switch exhaustively on `responseType` must add cases.
- **`OtplessAuthConfig` constructor gains an optional `deviceFingerprintMode` parameter** (defaults to `DeviceFingerprintMode.none`). Backwards compatible for positional callers.

## New features

- `setDeviceFingerprintMode(DeviceFingerprintMode)` — global default fingerprint strategy. Override per request by adding a `deviceFingerprintMode` key to the `start()` map.
- `setMfaEnabled(bool)` — enable MFA. Watch for `MFA_FACTOR_COMPLETED` in your response handler.
- `initSession(appId)` / `getActiveSession()` / `logoutSession()` — JWT-based session persistence.
- `startInBackground(callback, requestMap)` — Android-only silent variant of `start()` that suppresses `OTP_AUTO_READ` intermediates.
- Android-only: `checkSimBindingStatus()`, `clearSimBinding()`, `setSimBindingEnabled(bool)`, `closeDialogIfOpen()`.
- Extra keys accepted on the `start()` / `startInBackground()` request map: `tid`, `code`, `extras` (Map<String, String>), `requestId`, `deviceFingerprintMode`.

## Bug fix

- `sendUserAuthEvent(...)`: the `providerInfo` optional parameter was previously dropped due to an inverted null check on the plugin side. Fixed in 2.0.0; downstream analytics receive it now.


# Note


For complete documentation and other login feature explore, follow the following guide here:  [installation guide here](https://otpless.tech/docs/frontend-sdks/app-sdks/flutter/new/headless)

## Author

[OTPLESS](https://otpless.com), developer@otpless.com
