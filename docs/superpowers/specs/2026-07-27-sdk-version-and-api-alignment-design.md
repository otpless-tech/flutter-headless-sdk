# SDK Version Bump + Public API Alignment — Design

- **Repo:** `otpless_headless_flutter`
- **Author:** Digvijay Singh (design collaboration with Claude)
- **Date:** 2026-07-27
- **Target plugin version:** `2.0.0`

## 1. Goals

1. Bump the underlying native SDKs to their latest published versions.
   - Android AAR: `io.github.otpless-tech:otpless-headless-sdk` from `0.6.6` → `0.9.0`.
   - iOS pod: `OtplessBM/Core` from `2.0.8` → `2.3.2`.
2. Align the plugin's public Dart API with the current native surface — expose new native APIs and reduce the current Android/iOS asymmetry wherever both native SDKs actually support the capability.
3. Fix latent bugs found during the audit.
4. Update the changelog, platform matrix in the README, and the example app so consumers can adopt the new APIs.

## 2. Non-goals

- Introduce typed Dart request/response models. Request stays `Map<String, dynamic>`; response stays `dynamic`. New keys are documented but not enum-ified in Dart (except `DeviceFingerprintMode`, which is a new Dart enum because it is passed both globally and per-request).
- Expose iOS host-app integration APIs (`handleDeeplink`, `isOtplessDeeplink`, `registerFBApp`, `authorizeViaPasskey`) through Dart. These stay as client-side AppDelegate / SceneDelegate additions documented in the README.
- Expose `OtplessPhoneHint` (Google Credential Manager phone picker) via Dart in this release.
- Add automated tests beyond the existing platform-interface plumbing tests. Verification happens through the example app per `CLAUDE.md`.

## 3. Version-pin changes

Three files must be updated in lockstep:

| File | Line | Change |
|---|---|---|
| `pubspec.yaml` | `version:` | `1.1.1` → `2.0.0` |
| `android/build.gradle` | dependency line | `otpless-headless-sdk:0.6.6` → `otpless-headless-sdk:0.9.0` |
| `ios/otpless_headless_flutter.podspec` | `s.dependency 'OtplessBM/Core'` | `'2.0.8'` → `'2.3.2'` |
| `CHANGELOG.md` | top | Add `## 2.0.0` section describing the version bumps + API additions below |

The plugin version bump is a **major** because:
- The set of `responseType` values a consumer sees will grow (`AUTH_TERMINATED`, `MFA_FACTOR_COMPLETED`, `AUTO_FLOW_ACTION`). Callers that switch exhaustively will need to add cases.
- The existing `startBackground(callback, OtplessAuthConfig)` method is **renamed to `startOnetap(callback, OtplessAuthConfig)`** — the old name was misleading (it never launched a "background" auth; it launched the OneTap / verified-contact discovery sheet). It also changes on iOS from "no-op / returns false" to actually presenting an auth sheet.
- Two Dart method signatures gain new optional keys, but no method signature is removed.

## 4. New Dart public API on `Otpless`

Added in `lib/otpless_flutter.dart`. All go through `MethodChannelOtplessFlutter`.

### 4.1 Cross-platform methods (both native SDKs support)

```dart
Future<void> setDeviceFingerprintMode(DeviceFingerprintMode mode);
Future<void> setMfaEnabled(bool enabled);
Future<void> initSession(String appId);
Future<Map<String, dynamic>> getActiveSession(); // { "isActive": bool, "jwtToken": String? }
Future<void> logoutSession();
```

### 4.2 Android-only methods (no iOS equivalent in 2.3.2)

```dart
Future<void> startInBackground(OtplessResultCallback callback, Map<String, dynamic> jsonObject);
Future<bool> checkSimBindingStatus();
Future<void> clearSimBinding();
Future<void> setSimBindingEnabled(bool enabled);
Future<void> closeDialogIfOpen();
```

`startInBackground` maps to Android's `OtplessSDK.startInBackground(request, callback)` — the silent variant of `start` that does **not** emit an intermediate `OTP_AUTO_READ` response to the merchant; the SDK auto-reads the OTP and delivers only the final `ONETAP` / `VERIFY` response. It accepts the same request-map shape as `start` (see §5), including the five new keys.

On iOS all five of these methods are guarded in Dart by `Platform.isAndroid` and return early (`false` / `void`). Distinct from `startOnetap` (which is the cross-platform OneTap discovery flow — see §4.3) — see the platform matrix in §15 for the full picture.

`setSimBindingEnabled(bool)` writes to the Kotlin `var OtplessSDK.isSimBindingEnabled` property (declared at `OtplessSDK.kt:80`). The Kotlin `var` synthesizes a setter accessible from Java/Kotlin callers, and the plugin bridge just assigns it directly.

### 4.3 Existing methods with new behavior

| Method | Change |
|---|---|
| `startOnetap(callback, OtplessAuthConfig)` — was `startBackground` | **Renamed** for clarity: the flow presents the OneTap / verified-contact sheet, it is not a "background" auth. Signature is unchanged; still accepts a typed `OtplessAuthConfig` (see §6 for the new `deviceFingerprintMode` field on that class). Now cross-platform: iOS bridge routes to `Otpless.shared.startAuth(parent: rootVC, config: OtplessAuthCofig(...))` where `rootVC` is resolved by the SceneDelegate-safe helper introduced in commit `f4f2e8f`. Dart no longer guards this behind `Platform.isAndroid`. The old `startBackground` name is removed with the major version bump — no backward-compat shim. |
| `sendUserAuthEvent(...)` | Now cross-platform. iOS handler added. Dart no longer guards this behind `Platform.isAndroid`. **Bug fix**: `providerInfo` will actually be sent (see §7). |
| `start(callback, jsonObject)` | Same signature; accepts five new optional keys: `tid`, `extras`, `code`, `requestId`, `deviceFingerprintMode`. See §5. |

## 5. Request map — new keys

The keys below apply to the `Map<String, dynamic>` accepted by `start(...)` and `startInBackground(...)`. Both methods send the JSON-encoded map as `"arg"` on the channel; the Kotlin bridge parses it via the same `parseJsonToOtplessRequest` helper.

`startOnetap(...)` is a separate contract — it takes a typed `OtplessAuthConfig` (not a raw map), and its allowed fields are documented in §6. The two contracts do not overlap.

The following keys are added to the `start` / `startInBackground` map; all optional; all pass-through.

| Key | Type | Native call |
|---|---|---|
| `tid` | `String` | Android: `OtplessRequest.setTemplateId(value)`. iOS: `OtplessRequest.set(tid: value)`. Key name reuses the existing `"tid"` slot the Kotlin parser already reads at `utility.kt:62` — no dual-key logic needed. |
| `extras` | `Map<String, String>` | Android: `OtplessRequest.setExtras(value)`. iOS: `OtplessRequest.set(extras: value)` |
| `code` | `String` | Android: `OtplessRequest.setCode(value)`. iOS: `OtplessRequest.set(code: value)` |
| `requestId` | `String` | Android: `OtplessRequest.requestId = value`. iOS: `OtplessRequest.set(fromBackend: value)` |
| `deviceFingerprintMode` | `String` (`"none"` / `"async"` / `"sync"`) | Android: `OtplessRequest.deviceFingerprintMode = safeEnumValueOf<DeviceFingerprintMode>(...)`. iOS: `OtplessRequest.set(deviceFingerprintMode: ...)` |

`locale` is intentionally not added; the merchant confirmed it's not required for this release.

### 5.1 Parser hardening (Kotlin `utility.kt`)

The existing `parseJsonToOtplessRequest` in `android/src/main/kotlin/com/otpless/headlessflutter/utility.kt:28-69` needs to be hardened as part of this update. Four defects fixed in the same pass:

1. **`utility.kt:51`** — `json.getString("channelType")` throws `JSONException` when the caller supplies neither phone nor email nor channel. Switch to `optString` and skip the setter when the value is empty.
2. **`utility.kt:52`** — `OtplessChannelType.values().first { it.channelTypeName == channelType }` throws `NoSuchElementException` on unknown channels. Replace with `OtplessChannelType.fromString(channelType)`, which the SDK ships in 0.9.0 with a safe `WHATSAPP` fallback.
3. **`utility.kt:55-67`** — Optional-value setters (`setOtpLength`, `setExpiry`, `setTemplateId`, `setDeliveryChannel`) are called unconditionally with empty strings when the key is absent. Guard each with `if (value.isNotEmpty())` before calling the setter.
4. **Empty-map guard** — Same pattern for the new `extras` key: skip `setExtras` when the extras JSONObject is null or has zero keys.

New keys added by this update (per §5): `code`, `extras`, `requestId`, `deviceFingerprintMode`. `tid` is already read by the parser — no code change needed for that key, just documented as public in the Dart contract.

`parseToOtplessAuthConfig` (`utility.kt:71-74`) also gains a `deviceFingerprintMode` read on the `OtplessAuthConfig` — Android's config class supports the field.

The plugin-level default `defaultFingerprintMode` maintained for the global `setDeviceFingerprintMode` setter (§7) is applied **only when** the incoming request/config map does not include a `deviceFingerprintMode` key; explicit per-request values win over the global default.

## 6. Dart model additions — `lib/models.dart`

### 6.1 New enum

```dart
enum DeviceFingerprintMode { none, async, sync }
```

Mapping goes through the existing `camelCase → UPPER_SNAKE_CASE` bridge (`utility.kt#fromDartEnumStyleToKotlin`) on Android and a direct string-to-enum on iOS. The Kotlin `DeviceFingerprintMode` and Swift `DeviceFingerprintMode` both use `NONE / ASYNC / SYNC` case names, so the conversion works with zero custom code.

### 6.2 `OtplessAuthConfig` — new field

The Dart `OtplessAuthConfig` (consumed by `startOnetap(...)`) gains one new field:

```dart
class OtplessAuthConfig {
  final bool isForeground;
  final String? otp;
  final String? tid;
  final DeviceFingerprintMode deviceFingerprintMode; // NEW — defaults to DeviceFingerprintMode.none
  // toMap() serializes deviceFingerprintMode as the enum name string, matching the parser in §5.1.
}
```

Android's native `OtplessAuthConfig` (from `view/models/models.kt`) already carries a `deviceFingerprintMode` field with the same default of `NONE`, so `parseToOtplessAuthConfig` in `utility.kt:71-74` is extended to read it and pass it through.

iOS's native `OtplessAuthCofig` (spelled without the `n` — see typo note in §7) does **not** carry a `deviceFingerprintMode` field in 2.3.2; on iOS the Dart-side value is silently dropped and the global `Otpless.shared.setDeviceFingerprintMode` (§4.1) governs behavior. Documented in the README.

### 6.3 No other model changes

**No changes** to `AuthEvent`, `ProviderType`, `OTFooterType`, `OTButtonShape`, `OTVerifyOption`, `OTHeadingConsent`, `OTLoginPrefixText`, `OTCtaText`, `OTScope`, `OtplessTruecallerRequest`, or `OtplessTruecallerConfig` — the Android 0.9.0 source still defines all Truecaller enums with the same names (verified in `longclaw-truecaller/src/main/java/com/otpless/longclaw/tc/models.kt`).

## 7. Method channel — new / changed cases

Channel name unchanged: `otpless_headless_flutter`. The Dart→native method names below are new or newly implemented on the previously-missing platform.

| Method name | Args | Android handler | iOS handler |
|---|---|---|---|
| `setDeviceFingerprintMode` | `{ "mode": string }` | Android SDK has **no** global setter — only per-request. To honor the global-setter contract, the Kotlin bridge stores a `private var defaultFingerprintMode: DeviceFingerprintMode = NONE` and assigns it onto every `OtplessRequest` (built inside `start` / `startInBackground`) and every `OtplessAuthConfig` (built inside `startOnetap`) before dispatching to the SDK, unless the per-request map explicitly overrides it. | `Otpless.shared.setDeviceFingerprintMode(_:)` (native has a global setter) |
| `setMfaEnabled` | `{ "enabled": bool }` | `OtplessSDK.isMfaEnabled = enabled` | `Otpless.shared.setMfaEnabled(_:)` |
| `initSession` | `{ "appId": string }` | `lifecycleScope.launch(Dispatchers.IO) { OtplessSessionManager.init(context, appId) }` | `Task { await OtplessSessionManager.shared.initialize(appId: appId); DispatchQueue.main.async { result(nil) } }` |
| `getActiveSession` | none | `lifecycleScope.launch(Dispatchers.IO) { val s = OtplessSessionManager.getActiveSession(); … result.success(map) }`. Map is `{ "isActive": true, "jwtToken": "…" }` for `Active`, `{ "isActive": false }` for `Inactive`. | `Task { let s = await OtplessSessionManager.shared.getActiveSession(); let map = mapFrom(s); DispatchQueue.main.async { result(map) } }` — same map shape as Android |
| `logoutSession` | none | `lifecycleScope.launch(Dispatchers.IO) { OtplessSessionManager.logout(); result.success(null) }` | `Task { await OtplessSessionManager.shared.logout(); DispatchQueue.main.async { result(nil) } }` |
| `checkSimBindingStatus` | none | `lifecycleScope.launch(Dispatchers.IO) { val ok = OtplessSDK.checkSimBindingStatus(applicationContext); result.success(ok) }` | not handled (Dart guards) |
| `clearSimBinding` | none | `lifecycleScope.launch(Dispatchers.IO) { OtplessSDK.clearSimBinding(applicationContext); result.success(null) }` | not handled |
| `setSimBindingEnabled` | `{ "enabled": bool }` | `OtplessSDK.isSimBindingEnabled = enabled; result.success(null)` (sync, no dispatcher needed) | not handled |
| `closeDialogIfOpen` | none | `OtplessSDK.closeDialogIfOpen(); result.success(null)` | not handled |
| `startInBackground` | `{ "arg": jsonString }` | `lifecycleScope.launch(Dispatchers.IO) { OtplessSDK.startInBackground(request, onOtplessResponseCallback); result.success(null) }`. Request built via existing `parseJsonToOtplessRequest(...)` helper in `utility.kt:28` — the same one `start` uses — which is extended per §5.1 to read the four new keys not currently parsed (`extras`, `code`, `requestId`, `deviceFingerprintMode`). The existing `tid` slot is reused unchanged. | not handled (Dart guards) |
| `startOnetap` (**renamed** from `startBackground`) | `{ "arg": jsonString }` — JSON of the Dart `OtplessAuthConfig.toMap()` | Kotlin case is renamed to `"startOnetap"`. Handler: `lifecycleScope.launch(Dispatchers.IO) { OtplessSDK.start(parseToOtplessAuthConfig(json)) }`. `parseToOtplessAuthConfig` extended per §5.1 / §6.2 to read `deviceFingerprintMode`. | **new**: Swift case `"startOnetap"`. Handler: `Task { @MainActor in guard let rootVC = Self.rootViewController() else { result(false); return }; let ok = await Otpless.shared.startAuth(parent: rootVC, config: OtplessAuthCofig(isForeground: cfg.isForeground, otp: cfg.otp, tid: cfg.tid)); DispatchQueue.main.async { result(ok) } }`. Uses the existing `rootViewController()` helper at `SwiftOtplessFlutterHeadless.swift:136`. iOS's `OtplessAuthCofig` has no `deviceFingerprintMode` slot, so that field from Dart is dropped on iOS. |
| `sendUserAuthEvent` (existing name) | as today | unchanged | **new**: `Otpless.shared.userAuthEvent(event:fallback:providerType:providerInfo:)` |
| `initTrueCaller` (existing name) | as today | unchanged | **new**: return `false` — Truecaller SDK exists only on Android |
| `isWhatsAppInstalled` (existing name) | none | unchanged | **new**: return `false` — no iOS equivalent |

## 8. Bug fixes rolled into this release

1. **`sendUserAuthEvent` providerInfo inversion** — `lib/otpless_flutter_method_channel.dart:99` currently reads `if (providerInfo == null) "providerInfo": json.encode(providerInfo)`. This means `providerInfo` is only added when it's null and then json-encoding null gets attached — the opposite of intent. Fix: `if (providerInfo != null) "providerInfo": json.encode(providerInfo)`.

2. **iOS switch coverage** — the current `SwiftOtplessFlutterHeadless.handle` only handles seven methods; five cases fall through to `default: return`. This design fills those five (`isWhatsAppInstalled`, `initTrueCaller`, `startOnetap` — the previously-named `startBackground` channel case, `sendUserAuthEvent`, `closeDialogIfOpen`) so `MissingPluginException` is never raised from iOS for any documented method.

## 9. iOS AppDelegate / SceneDelegate integration — README-only

Not wrapped in Dart. README grows a new section: "iOS AppDelegate / SceneDelegate integration". It documents, with copy-paste Swift snippets, when a client must call:

- `Otpless.shared.handleDeeplink(url)` — from the app's URL scheme handler
- `Otpless.shared.isOtplessDeeplink(url)` — optional URL pre-filter
- `Otpless.shared.registerFBApp(...)` — three overloads, only if the app uses `FACEBOOK_SDK` channel
- `Otpless.shared.authorizeViaPasskey(withRequest:windowScene:)` — only if the app uses WebAuthn / passkey authentication

The README also notes that the `OtplessBM/Core` podspec pulls only the base module. Merchants using `GOOGLE_SDK` or `FACEBOOK_SDK` channels must add the appropriate subspec (`OtplessBM/GoogleSupport`, `OtplessBM/FacebookSupport`) in their own Podfile.

## 10. Response contract — new `responseType` values

The callback map delivered by the plugin remains `{ statusCode, responseType, response }`. The following new values may appear:

- `AUTH_TERMINATED` — final failure state (user aborted, SNA timeout, provider error). Response body contains `errorCode`, `errorMessage`, and optionally `snaError`.
- `MFA_FACTOR_COMPLETED` — one MFA factor cleared; response contains `authType` and `communicationChannel`.
- `AUTO_FLOW_ACTION` — user action in auto-flow (Android only in 0.9.0). Response contains `actionType` and `actionDescription`, or an error pair.

README's "response type" section gets a new subsection listing these three with example payloads and a call-out that `AUTO_FLOW_ACTION` will not arrive on iOS.

## 11. Files touched

Production code:

- `pubspec.yaml`
- `CHANGELOG.md`
- `README.md`
- `lib/otpless_flutter.dart`
- `lib/otpless_flutter_method_channel.dart`
- `lib/models.dart`
- `android/build.gradle`
- `android/src/main/kotlin/com/otpless/headlessflutter/OtplessFlutterHeadless.kt`
- `android/src/main/kotlin/com/otpless/headlessflutter/utility.kt` — `parseJsonToOtplessRequest` and `parseToOtplessAuthConfig` are hardened and extended per §5.1: four new keys read, four defects (JSONException on missing channel, NoSuchElementException on unknown channel, empty-string setters, missing extras) fixed. `DeviceFingerprintMode` round-trips through the existing `safeEnumValueOf<T>` + `fromDartEnumStyleToKotlin` helpers with no changes to those helpers.
- `ios/otpless_headless_flutter.podspec`
- `ios/Classes/SwiftOtplessFlutterHeadless.swift`

Example app:

- `example/lib/main.dart` — rename any `startBackground(...)` call site to `startOnetap(...)`, add a small toggle for `setMfaEnabled`, a button that calls `getActiveSession()` and prints the result, and confirm `startOnetap` now runs on iOS.

## 12. Threading contract (unchanged pattern, applied to new methods)

- **Android**: all suspending SDK calls (`OtplessSessionManager.init` / `getActiveSession` / `logout`, `checkSimBindingStatus`, `clearSimBinding`) go through `activity.lifecycleScope.launch(Dispatchers.IO) { ... }`. The native `OtplessSessionManager.logout()` retains its original Kotlin name — only the Dart-facing method and channel key are called `logoutSession`. Non-suspending property setters and `closeDialogIfOpen` run inline.
- **iOS**: every new switch case that touches `Otpless.shared` follows the existing `Task { @MainActor [weak self] in ... }` pattern (matches the file's actor-isolation contract for the main SDK). `OtplessSessionManager.shared` is a **separate `public actor`** (not `@MainActor`); calls to `initialize`, `getActiveSession`, and `logout` are `await`ed inside a plain `Task { ... }` — no `@MainActor` hop is required for the actor calls themselves. The final `result(...)` marshaling back onto the FlutterResult continuation still hops to the main thread via `DispatchQueue.main.async` (existing helper pattern) because Flutter's platform channel expects main-thread result delivery.

## 13. Rollout / validation

1. Run `flutter analyze` and `flutter test` on the plugin. No regressions expected — tests only cover platform-interface plumbing.
2. `cd example && flutter run` on an Android device. Verify `initialize` → `start` → OTP → verify path. Verify new: `setMfaEnabled`, `getActiveSession`, `startOnetap`, `startInBackground`, `setDeviceFingerprintMode` per-request.
3. Same on an iOS device (physical, iOS 15+ for OneTap). Verify `startOnetap` now presents a sheet. Verify `initSession` → `getActiveSession` → `logoutSession`.
4. `flutter pub publish --dry-run` before shipping.

## 14. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Android 0.9.0 introduces a subtle behavior change on the standard `start` path (e.g., new response type ordering) that breaks an existing merchant flow. | Document all new response types in the README and CHANGELOG. Existing consumers who only switch on the current values should still work because none of the old response types were removed. |
| iOS `startAuth` (invoked from Dart via the renamed `startOnetap`) requires a `parent: UIViewController` and iOS 15+. Client apps still on iOS 13/14 or without a resolvable root VC hit a runtime failure. | The `rootViewController()` helper at `SwiftOtplessFlutterHeadless.swift:136` (added in `f4f2e8f`) handles SceneDelegate apps. If it returns `nil`, the bridge calls `result(false)` and logs. Behavior parity with prior "no-op" state is preserved. |
| Consumers who upgrade from 1.x will hit a compile error the first time they call `otpless.startBackground(...)` because the method is renamed to `startOnetap`. | Called out prominently in CHANGELOG under "Breaking changes" and in the README migration section. This is a deliberate part of the 2.0.0 bump; a rename shim was rejected because it perpetuates the misleading name. |
| `OtplessSessionManager.init` on Android is a suspending call; a caller might call `getActiveSession` before it completes. | The Kotlin bridge holds a `Job` from init and, on `getActiveSession`, awaits it before calling through. Alternative: return an `Inactive` state immediately if init hasn't finished. Chosen: await, since it matches iOS actor semantics. |
| Provider-info bug fix silently changes the shape of `sendUserAuthEvent` calls on the wire — a downstream analytics pipeline that keyed off the buggy behavior could break. | Extremely unlikely (the current buggy path never sent user-defined data). Note in CHANGELOG as a bug fix, not a feature. |

## 15. Platform matrix (goes into README as-is)

| Dart method | Android | iOS |
|---|:---:|:---:|
| `initialize` | ✅ | ✅ |
| `setResponseCallback` | ✅ | ✅ |
| `setDevLogging` | ✅ | ✅ |
| `start` | ✅ | ✅ |
| `startOnetap` (OneTap discovery) — renamed from `startBackground` | ✅ | ✅ *(new)* |
| `commitResponse` | ✅ | ✅ |
| `isSdkReady` | ✅ | ✅ |
| `sendUserAuthEvent` | ✅ | ✅ *(new)* |
| `setDeviceFingerprintMode` | ✅ | ✅ |
| `setMfaEnabled` | ✅ | ✅ |
| `initSession` / `getActiveSession` / `logoutSession` | ✅ | ✅ |
| `startInBackground` (silent regular auth) | ✅ | ❌ (no SDK equivalent) |
| `isWhatsAppInstalledForAndroid` | ✅ | ❌ returns `false` |
| `initTrueCaller` | ✅ | ❌ returns `false` (no iOS Truecaller SDK) |
| `checkSimBindingStatus` / `clearSimBinding` / `setSimBindingEnabled` | ✅ | ❌ (no SDK equivalent) |
| `closeDialogIfOpen` | ✅ | ❌ (no SDK equivalent) |
| Deep-link handling / Passkey / Facebook SDK register | via manifest / no-op | client wires up in `AppDelegate` / `SceneDelegate` (see README) |
