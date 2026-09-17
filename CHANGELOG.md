## 3.0.1 (17th September 2026)
### Changes
- Wrapper attribution: the plugin now declares itself to the native SDKs at `initialize`, so backend telemetry attributes the session to the Flutter wrapper rather than to a plain native integration. The device event reports `platform = "otpless-headless-sdk(flutter)"` on Android and `platform = "otpless-headless(flutter)"` on iOS.
- The value is hardcoded to `"flutter"` and is **not** merchant-facing: there is no new Dart parameter, no change to the `initialize` method-channel payload, and no behaviour change in any auth flow. Purely additive; no migration needed from 3.0.0.
- Requires `OtplessBM/Core 3.0.1` (iOS) and `otpless-headless-sdk 2.0.1` (Android, unchanged).

## 3.0.0 (16th September 2026)
### Breaking
- `initialize(..., timeout:)` has been removed. It was never read by either native SDK and was not sent over the method channel; drop `timeout:` from your call site.

### Features
- `initialize(appId, sslPinning: OtplessSslPinning.enabled)` opts in to SSL certificate pinning of the OTPLESS backend on both Android and iOS. Default is `OtplessSslPinning.disabled`, so existing integrations are unchanged. When enabled and validation fails, the SDK fails closed and the response callback receives `responseType: "FAILED"`, `statusCode: 5004`, `response: {"errorCode": "5004", "errorMessage": "SSL pin validation failed"}`; no auth request leaves the device.
- `initialize(appId, loginUri: ...)` is now honoured on both platforms (it was previously impossible to set from Dart).
- Android: Google Play Integrity attestation ships inside `otpless-headless-sdk 2.0.1`. It is internal to the SDK and needs no plugin API.

### Changes
- Android: bump `otpless-headless-sdk` `0.9.0` → `2.0.1`.
- iOS: bump `OtplessBM/Core` `2.3.2` → `3.0.0`; production host is now `sigma.otpless.app`.
- iOS: the response delegate is bound inside `initialize` (parity with Android), so a `FAILED` emitted before `setResponseCallback` is no longer dropped.
- Dart: the response-callback dispatcher is null-safe; a native event arriving before `setResponseCallback` no longer throws.
- Podspec `s.version` now tracks `pubspec.yaml` (was stuck at `0.0.1`).

## 2.0.0 (27th July 2026)
### Breaking
- Renamed `startBackground(callback, config)` → `startOnetap(callback, config)`. Update all Dart call sites. See README migration section.
- Response type set grew: consumers may now receive `AUTH_TERMINATED`, `MFA_FACTOR_COMPLETED`, and (Android only) `AUTO_FLOW_ACTION` from the response callback.
- Toolchain: Android consumers need Android Gradle Plugin 8.9.1+ and `compileSdkVersion` 36+ (transitive AndroidX requirement of `otpless-headless-sdk:0.9.0`).

### Android
- Bump `otpless-headless-sdk` to `v0.9.0`.
- New public APIs: `setMfaEnabled`, `initSession`, `getActiveSession`, `logoutSession`, `startInBackground`, `checkSimBindingStatus`, `clearSimBinding`, `setSimBindingEnabled`, `closeDialogIfOpen`.
- Request-parser hardening: guards against unknown channels and empty-string setters; now accepts `code`, `extras`, `requestId`, `deviceFingerprintMode` on the `start` / `startInBackground` request map.


### iOS
- Bump `OtplessBM/Core` to `2.3.2`.
- `startOnetap`, `sendUserAuthEvent` now execute on iOS (were previously no-ops).
- New public APIs mirroring Android: `setMfaEnabled`, `initSession`, `getActiveSession`, `logoutSession`.


## 1.1.1 (19th Jun 2026)
### iOS
- [fix] SceneDelegate support in `initialize` root VC lookup

## 1.1.0 (12th Feb 2026)
### Android
- [fix] security exception and mutex fix
- [fix] android sdk update 0.6.6

## 1.0.9 (5th Feb 2026)
### iOS
- [fix] OtplessBM updated to 2.0.8 for actor fix

## 1.0.8 (2nd Feb 2026)
### iOS
- [feat] Airtel and Vi Support


## 1.0.7 (28th Jan 2026)
### Andriod
- [fix] Truecaller initialization switched to io thread


## 1.0.6 (15th Jan 2026)
### Android
- Update `otpless-headless-sdk` to `v0.6.3`
- Passkey support
- Background auth support
- Airtel and Vi support

## 1.0.5 (28th November 2025)
### Android
- Update `otpless-headless-sdk` to `v0.3.8`
- Update Truecaller low memory fix


## 1.0.4 (29th August 2025)
### Android
- Updated `otpless-headless-sdk` to `v0.3.4`
- isSdkReady support

### iOS
- Updated `OtplessBM` to `v2.0.0`
- isSdkReady support 

## 1.0.3 (16th July 2025)
### Android
- Updated `otpless-headless-sdk` to `v0.3.1`
- Added support for **SNA only** mode

### iOS
- Updated `OtplessBM` to `v1.1.7`
- Added support for **SNA only** mode

## 1.0.2 (3rd July 2025)
#### Feature
* truecaller support
* android sdk update to 0.3.0
* ios sdk update to 1.1.6

## 1.0.1 (16th April 2025)
### Fixes
* Fixed incorrect plugin channel name issue.

## 1.0.0 (8th April 2025)

* First release of `Flutter Headless SDK`