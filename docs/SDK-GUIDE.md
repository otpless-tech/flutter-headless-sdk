# SDK-GUIDE — otpless_headless_flutter

Canonical, exhaustive description of the OTPLESS headless Flutter plugin. Written against **plugin 2.0.0** (`0e2e86d`), pinning `io.github.otpless-tech:otpless-headless-sdk:0.9.0` (Android) and `OtplessBM/Core 2.3.2` (iOS).

**§ numbers are stable identifiers** referenced from `CLAUDE.md`, the skills, and PR reviews. Never renumber; add sub-sections instead.

Every statement here was verified against source. Where the code and the README disagree, this guide states what the **code** does and flags the discrepancy in §15.

---

## §1 What this is, and what it is not

This is a **wrapper**. It contains **no authentication logic, no networking, no telemetry, no persistence, and no response construction**. Its entire job is to marshal:

- Dart method calls → a `MethodChannel` → the native OTPLESS SDK
- native responses → a JSON string → back over the same channel → a Dart callback

Consequences that shape everything below:

1. **Nothing here defines behavior.** If a merchant asks "why did the SDK return 7160", the answer is in android-full's or ios-headless's guide, not this one.
2. **The response contract is not ours to change.** It is backend-driven and shared across android-full, iOS, and the RN wrappers. This plugin must pass payloads through **verbatim** (hub rule 4).
3. **The channel is the only real contract this repo owns** — and it is a stringly typed one spanning three languages with no compiler between them (§3).

Sibling wrapper: `otpless-rn-full` pins the same two native SDKs. Changes here usually apply there.

## §2 Architecture & layout

```
lib/
  otpless_flutter.dart                  §4.1  public API — the `Otpless` class merchants use
  models.dart                           §4.2  request/config models + enums (wire format)
  otpless_flutter_method_channel.dart   §3,§5 the channel: invokeMethod calls + response handler
  otpless_flutter_platform_interface.dart §4.3 plugin_platform_interface plumbing
android/
  build.gradle                          §13   Android toolchain + the native pin
  src/main/kotlin/com/otpless/headlessflutter/
    OtplessFlutterHeadless.kt           §5,§6 FlutterPlugin: onMethodCall dispatch + lifecycle
    utility.kt                          §8    request parsing, response conversion, enum mapping
ios/
  otpless_headless_flutter.podspec      §13   iOS deployment target + the native pin
  Classes/
    SwiftOtplessFlutterHeadless.swift   §5,§6 FlutterPlugin: handle() dispatch + delegates
    WhatsAppHandler.swift               §15.11 DEAD CODE (legacy, unreferenced)
    Strings.swift                       §15.11 DEAD CODE (legacy, unreferenced)
example/                                §14   testbed — never documented, but the only native build proof
test/                                   §14   Dart-only tests
api/dart-surface.txt                    §4    committed public-API golden
scripts/                                §14   dart_surface.py, docs-verify.sh
```

Source-file → section map:

| File | Primary sections |
|---|---|
| `lib/otpless_flutter.dart` | §4.1, §5 |
| `lib/models.dart` | §4.2, §8.2, §8.3, §8.4 |
| `lib/otpless_flutter_method_channel.dart` | §3, §5, §7.3, §9 |
| `lib/otpless_flutter_platform_interface.dart` | §4.3, §15.1 |
| `android/.../OtplessFlutterHeadless.kt` | §5, §6, §7.3 |
| `android/.../utility.kt` | §8, §11.2, §15.2, §15.7 |
| `ios/.../SwiftOtplessFlutterHeadless.swift` | §5, §6, §7.3, §15.3, §15.4 |

### §2.1 Three layers, five files per feature

Adding one channel method touches five files (Dart API, Dart channel, Kotlin, Swift, golden). See the **bridge-method** skill. There is no code generation and no shared schema — the layers are held together only by matching string literals and by `scripts/docs-verify.sh` check 3.

## §3 The method-channel contract

| Property | Value |
|---|---|
| Method channel | `MethodChannel('otpless_headless_flutter')` |
| Reverse invocation (native → Dart) | method name `otpless_callback_event` **on the same method channel** |
| Declared but unused | `EventChannel('otpless_callback_event')` — see §15.5 |
| Dart → native encoding | scalars as plain argument keys; **request maps as a JSON string** under the key `arg` |
| native → Dart encoding | a **JSON string** as the sole positional argument |

### §3.1 Encoding conventions — and why they matter

Two different conventions coexist, and mixing them is a silent failure:

- **Scalar arguments** go as a plain map: `invokeMethod("setMfaEnabled", {'enabled': true})`. Kotlin reads `call.argument<Boolean>("enabled")`; Swift reads `args["enabled"] as? Bool`.
- **Request payloads** are `json.encode`d into a single `arg` key: `invokeMethod("start", {'arg': json.encode(jsonObject)})`. Kotlin decodes via `MethodCall.parseJsonArg()`; Swift via `JSONSerialization`.

Methods using the `arg` JSON-string convention: `start`, `startOnetap`, `startInBackground`. Everything else uses plain keys.

A payload sent as a raw `Map` where the other side expects a JSON string does not fail to compile; it fails at runtime as a cast error or a silently empty request.

### §3.2 Response direction

Native builds `{responseType, statusCode, response}`, serializes it to a JSON **string**, and invokes `otpless_callback_event`. Dart's `setMethodCallHandler` decodes it with `jsonDecode` and hands the resulting `dynamic` to the registered callback (§7).

## §4 Public Dart API

The mechanical contract is `api/dart-surface.txt`, regenerated by `make surface-dump`. It intentionally records **parameter names** (Dart callers use named arguments) and **enum values in source order** (`.name` is the wire value — §8.4), so renaming either shows as a reviewed diff.

### §4.1 `Otpless` — the class merchants use

`lib/otpless_flutter.dart`. A thin facade: every method delegates to a private `MethodChannelOtplessFlutter` instance, except `getPlatformVersion` (§15.1).

Note it constructs its **own** `MethodChannelOtplessFlutter` in a field initializer rather than using `OtplessFlutterPlatform.instance`. So `Otpless()` bypasses the platform-interface indirection for all 19 real methods.

### §4.2 Models and enums (`lib/models.dart`)

| Type | Purpose | Wire form |
|---|---|---|
| `OtplessAuthConfig` | onetap/foreground auth config | `toMap()` → `isForeground`, `otp?`, `tid?`, `deviceFingerprintMode` |
| `OtplessTruecallerRequest` | TrueCaller init | `toMap()` → `config?`, `scopes[]` |
| `OtplessTruecallerConfig` | TrueCaller UI customisation | `toMap()` → 9 optional keys (§8.3) |
| `AuthEvent` | `authInitiated`, `authSuccess`, `authFailed` | `.name` |
| `ProviderType` | `client`, `otpless` | `.name` |
| `DeviceFingerprintMode` | `none`, `async`, `sync` | `.name` |
| `OTScope` | `profile`, `phone`, `openId`, `offlineAccess`, `email`, `address` | `.name` |
| `OTFooterType`, `OTButtonShape`, `OTVerifyOption`, `OTHeadingConsent`, `OTLoginPrefixText`, `OTCtaText` | TrueCaller UI enums | `.name` |

`OtplessAuthConfig.toMap()` omits `otp`/`tid` when null but **always** emits `deviceFingerprintMode`.

### §4.3 Platform interface (`otpless_flutter_platform_interface.dart`)

Standard `plugin_platform_interface` scaffolding: an abstract `OtplessFlutterPlatform` with a token, a settable `instance`, and exactly one method — `getPlatformVersion()`, which **throws `UnimplementedError`**. `MethodChannelOtplessFlutter` does not override it (§15.1).

### §4.4 Typedefs

- `OtplessResultCallback = void Function(dynamic)` — the response callback. Untyped by design: payloads are backend-driven and passed through verbatim.
- `OtplessSimEventListener = void Function(List<Map<String, dynamic>>)` — declared, **never used** anywhere in the plugin (§15.11).

## §5 Channel method catalog

All 19 channel methods. "A" = Android behavior, "i" = iOS behavior. `result` column records whether the Dart `Future` is guaranteed to complete.

| Dart method | Channel name | Android | iOS | `result` answered? |
|---|---|---|---|---|
| `initialize(appId, {timeout})` | `initialize` | `OtplessSDK.initialize(appId, activity, loginUri, cb)` on `Dispatchers.IO`; errors if no activity | `Otpless.shared.initialise(withAppId:vc:)`; no-op if no root VC | both ✅ |
| `setResponseCallback(cb)` | `setResponseCallback` | `OtplessSDK.setResponseCallback` | `setResponseDelegate(self)` | both ✅ |
| `start(cb, map)` | `start` | `OtplessSDK.start(request, cb)`; cancels prior job unless OTP verification | `Otpless.shared.start(withRequest:)`; same cancel rule | both ✅ (before work) |
| `startInBackground(cb, map)` | `startInBackground` | `OtplessSDK.startInBackground(...)` | **no-op**, returns `nil` | both ✅ |
| `startOnetap(cb, config)` | `startOnetap` | `OtplessSDK.start(authConfig)` → `Bool` | `Otpless.shared.startAuth(parent:config:)` → `Bool` | both ✅ |
| `commitResponse(response)` | `commitResponse` | `OtplessSDK.commit(...)` | `commitOtplessResponse(...)` | **A: ❌ never** (§15.2) / i: ✅ |
| `isSdkReady()` | `isSdkReady` | `OtplessSDK.isSdkReady` | `Otpless.shared.isSdkReady()` | both ✅ |
| `setDevLogging(bool)` | `setDevLogging` | `OtplessSDK.devLogging = value` | installs logger delegate **only when true** (§15.4) | both ✅ |
| `setMfaEnabled(bool)` | `setMfaEnabled` | `OtplessSDK.isMfaEnabled` | `setMfaEnabled(_:)` | both ✅ |
| `initSession(appId)` | `initSession` | `OtplessSessionManager.init(context, appId)`; errors on empty appId | `OtplessSessionManager.shared.initialize(appId:)` | both ✅ |
| `getActiveSession()` | `getActiveSession` | `{isActive, jwtToken?}` | `{isActive, jwtToken?}` | both ✅ |
| `logoutSession()` | `logoutSession` | `OtplessSessionManager.logout()` | `logout()` | both ✅ |
| `sendUserAuthEvent(...)` | `userAuthEvent` | `OtplessSDK.userAuthEvent(...)` → `true` | same → `true` | both ✅ |
| `initTrueCaller(request?)` | `initTrueCaller` | `OtplessSDK.initTrueCaller(...)`; failure emits an `AUTH_FAILED` event | **returns `false`** | both ✅ |
| `isWhatsAppInstalledForAndroid()` → `isWhatsAppInstalled()` | `isWhatsAppInstalled` | `OtplessUtils.isWhatsAppInstalled(activity)` | **returns `false`** | both ✅ |
| `checkSimBindingStatus()` | `checkSimBindingStatus` | `OtplessSDK.checkSimBindingStatus(context)` | **returns `false`** | both ✅ |
| `clearSimBinding()` | `clearSimBinding` | `OtplessSDK.clearSimBinding(context)` | **no-op** | both ✅ |
| `setSimBindingEnabled(bool)` | `setSimBindingEnabled` | `OtplessSDK.isSimBindingEnabled` | **no-op** | both ✅ |
| `closeDialogIfOpen()` | `closeDialogIfOpen` | `OtplessSDK.closeDialogIfOpen()` | **no-op** | both ✅ |
| *(none — unreachable)* | `cleanup` | cancels job + `OtplessSDK.cleanup()` | cancels task + `cleanup()` | **A: ❌ never** / i: ✅ — but no Dart caller (§15.6) |

### §5.1 Dart-side platform guards

`MethodChannelOtplessFlutter` returns early on non-Android **before** touching the channel for: `isWhatsAppInstalled`, `initTrueCaller`, `startInBackground`, `closeDialogIfOpen`, `checkSimBindingStatus`, `clearSimBinding`, `setSimBindingEnabled`.

So the iOS handlers for those are **defensive only** — unreachable through the current public API. Keep them: they are the safety net if a guard is ever dropped. This is the established pattern for an Android-only capability (see the **bridge-method** skill).

### §5.2 Unknown-method behavior differs

- Android: `else -> result.notImplemented()` → Dart throws `MissingPluginException`. Correct.
- iOS: `default: return` → **`result` is never called**, so the Dart `Future` never completes (§15.3).

## §6 Flows end-to-end

### §6.1 Initialization

1. Merchant calls `initialize(appId)`, optionally `setResponseCallback(cb)`.
2. **Android:** requires an attached `FragmentActivity` (held as a `WeakReference`, set in `onAttachedToActivity`). If absent → `result.error("0", "init called before activity is attached")`. Otherwise `lifecycleScope.launch(Dispatchers.IO)` → `OtplessSDK.initialize(appId, activity, loginUri, ::onOtplessResponseCallback)`.
3. **iOS:** resolves a root view controller (`rootViewController()`, which handles SceneDelegate apps, then AppDelegate-only, then a legacy fallback). If none → `result(nil)` and **initialization silently does not happen**.
4. The native SDK later emits `SDK_READY` (or `FAILED`) through the response path (§7.3).

Ordering hazard: `initialize` registers the response callback natively, so `SDK_READY` can arrive **before** the merchant calls `setResponseCallback`. In Dart, `_callback` is then still null and the handler force-unwraps it (§15.7).

### §6.2 Phone / OTP authentication

1. `start(cb, {...})` — the map is JSON-encoded under `arg` (§3.1).
2. Both natives compute `isOtpVerification` as "the request has a non-empty `otp`". If **not** an OTP verification, the previous in-flight job/task is cancelled; if it is, the prior job is left running and not tracked. Identical logic on both platforms.
3. Native emits `INITIATE`, then `OTP_AUTO_READ` / `DELIVERY_STATUS` / `ONETAP` / `VERIFY` / `FAILED` as the flow proceeds.
4. Merchant calls `commitResponse(response)` to acknowledge (§7.4).

### §6.3 One-tap / foreground auth

`startOnetap(cb, OtplessAuthConfig)` → config JSON-encoded under `arg` → `Bool`.

**Divergence:** Kotlin's `parseToOtplessAuthConfig` reads `isForeground`, `otp`, `tid` **and `deviceFingerprintMode`**. Swift's handler reads only `isForeground`, `otp`, `tid` — it constructs `OtplessAuthCofig(isForeground:otp:tid:)` and **drops `deviceFingerprintMode`** (§15.8).

### §6.4 Background auth

`startInBackground` is Android-only (guarded in Dart, §5.1) → `OtplessSDK.startInBackground`, cancelling any prior job unconditionally.

### §6.5 TrueCaller (Android only)

`initTrueCaller(request?)` → `parseOtplessTruecallerRequest` (§8.3) → `OtplessSDK.initTrueCaller(activity, config) { OTScopeRequest.ActivityRequest(activity, scopes) }`.

On exception, the bridge **swallows it** and reports telemetry instead: `userAuthEvent(AUTH_FAILED, false, OTPLESS, {error: "truecaller_init_failed", errorMessage: ...})`, then returns `false`. This is the constitution's "fail safe, not loud" pattern applied correctly.

### §6.6 Session management

`initSession(appId)` → `getActiveSession()` → `logoutSession()`. Implemented on **both** platforms via `OtplessSessionManager`. `getActiveSession` returns `{isActive: true, jwtToken: <jwt>}` or `{isActive: false}`; Dart coerces a non-`Map` result to `{'isActive': false}`.

### §6.7 SIM binding (Android only)

`checkSimBindingStatus`, `clearSimBinding`, `setSimBindingEnabled` — all Dart-guarded to Android (§5.1).

### §6.8 User auth events

`sendUserAuthEvent(event, fallback, providerType, {providerInfo})`. `providerInfo` is **JSON-encoded to a string** in Dart, then decoded natively.

- Android: `safeEnumValueOf<AuthEvent>` converts `authInitiated` → `AUTH_INITIATED` (§8.4). Values that stringify empty are **dropped** from `providerInfo`. Returns `false` if any of event/fallback/providerType is missing.
- iOS: lowercases and matches literals (`"authinitiated"`, `"authsuccess"`, `"authfailed"`); anything else → `result(false)`. `providerType` is `.OTPLESS` only when the lowercased string equals `"otpless"`, else `.CLIENT` — so a typo silently becomes `CLIENT` rather than an error. Every `providerInfo` value is stringified with `"\(v)"`.

## §7 The response contract

### §7.1 Envelope

```json
{ "responseType": "<enum name>", "statusCode": <int>, "response": { ... } }
```

Delivered to Dart as a **JSON string**, decoded to `dynamic`. The plugin never inspects or reshapes `response` — it is backend-driven and shared with android-full / iOS / rn-full (hub rule 4).

### §7.2 Response types

Owned by the natives, not by this plugin. As of the pinned versions, android-full's `ResponseTypes` has: `INITIATE`, `VERIFY`, `ONETAP`, `OTP_AUTO_READ`, `FALLBACK_TRIGGERED`, `FAILED`, `SDK_READY`, `DELIVERY_STATUS`, `AUTH_TERMINATED`, `AUTO_FLOW_ACTION`, `MFA_FACTOR_COMPLETED`. iOS's set is the same **minus `OTP_AUTO_READ` and `AUTO_FLOW_ACTION`**.

Therefore, from Flutter: **`OTP_AUTO_READ` and `AUTO_FLOW_ACTION` can only ever arrive on Android.** A merchant's `switch` must tolerate that asymmetry. Never hardcode this list in Dart — it is a native concern and would drift.

### §7.3 Marshalling, both directions

**Native → Dart:**
- Android: `convertHeadlessResponseToJson` builds a `JSONObject` with `responseType` (the enum, stringified by org.json), `statusCode`, `response`, then `channel.invokeMethod("otpless_callback_event", json.toString())`.
- iOS: builds `["statusCode":, "responseType": rawValue, "response":]`, serializes with `JSONSerialization`, and invokes through `ChannelManager.shared` (a `@MainActor` singleton holding the channel).
- Dart: `jsonDecode` → `_callback!(result)`.

**Dart → native (commit only):**
- Android: `convertMapToOtplessResponse` — `ResponseTypes.valueOf(responseType)`, `JSONObject(response as Map)`, and `statusCode.toString().softParseStatusCode()` which yields **`-1000`** on a non-integer. The whole conversion is wrapped in `try/catch` returning `null` on any failure, and `OtplessSDK.commit` accepts null.
- iOS: `convertDictionaryToOtplessResponse` — unknown `responseType` falls back to **`.FAILED`**, and a missing `statusCode` becomes **`-25000`**.

Those two sentinels (`-1000` vs `-25000`) and the two failure modes (null vs `.FAILED`) are **not** aligned across platforms. Neither is documented merchant-side.

### §7.4 Commit

`commitResponse(response)` hands a response back to the native SDK to acknowledge it. The README's example calls it at the top of every response callback.

**It is not awaitable on Android** — the Kotlin handler never calls `result` (§15.2). The README pattern does not `await`, so nothing appears broken; but each call leaks a `Future` that never completes, and `await otpless.commitResponse(r)` hangs forever on Android while returning normally on iOS.

## §8 Request marshalling

### §8.1 `start` / `startInBackground` request keys

Parsed by `parseJsonToOtplessRequest` (Kotlin) and `createOtplessRequest` (Swift).

| Key | Android | iOS |
|---|---|---|
| `phone` + `countryCode` | `setPhoneNumber(number, countryCode)` when `phone` non-empty (`countryCode` read via `optString`, so `""` if absent) | requires `phone` non-empty **and** `countryCode` present as a `String` |
| `email` | `setEmail` | `set(email:)` |
| `channelType` | `OtplessChannelType.fromString(raw)` | `fromString(raw.uppercased())` |
| `otp`, `code`, `otpLength`, `expiry`, `tid`, `deliveryChannel`, `requestId` | each applied when non-empty; `tid` → `setTemplateId`, `requestId` → `requestId` | same, `requestId` → `set(fromBackend:)` |
| `extras` | `optJSONObject`; entries with empty string values are dropped | `args["extras"] as? [String: String]` — a non-`String` value makes the **whole cast fail** and all extras are dropped |
| `deviceFingerprintMode` | `safeEnumValueOf<DeviceFingerprintMode>` (§8.4) | `switch` on `.uppercased()`: `ASYNC`/`SYNC`/`NONE`, else ignored |

Selection of identifier is `when { phone → … email → … channelType → … }` on Android and the equivalent `if/else if` on iOS: **first match wins**, so sending both `phone` and `email` silently uses `phone`.

Two asymmetries worth noting: iOS requires `countryCode` to be present alongside `phone` (Android tolerates its absence with `""`), and `extras` typing is stricter on iOS.

`deliveryChannel` is uppercased on iOS (`deliveryChannel.uppercased()`) but passed through as-is on Android — the same divergence the hub logs as `PARITY.md` B2/B4 for the RN wrappers. It is systemic across all three wrappers.

### §8.2 `startOnetap` config

`parseToOtplessAuthConfig` (Kotlin): `isForeground` (default `false`), `otp` via `optString` (so `""` not null when absent), `tid` nulled when empty, `deviceFingerprintMode` defaulting to `NONE`. Swift reads only the first three (§15.8).

### §8.3 TrueCaller config (Android only)

`parseOtplessTruecallerRequest` → `parseTrueCallerConfig`. Six enum fields via `safeEnumValueOf`, plus:

- `locale` → `parseLocale`: splits on `-` **or** `_`, and returns a `Locale` **only when exactly two parts result**. So `"en-US"` works, `"en"` yields **null**, `"en-US-POSIX"` yields null. Hand-rolled rather than `Locale.forLanguageTag` — matches `PARITY.md` B6.
- `buttonColor`, `buttonTextColor` → `parseHexColor` via `Color.parseColor`, null on failure.

Absent `request` or absent `scopes` both default to `[PHONE, OPEN_ID, PROFILE]`. Non-`String` scope entries are skipped.

### §8.4 Dart→Kotlin enum conversion

`String.fromDartEnumStyleToKotlin()` inserts `_` at lowerCamelCase boundaries and uppercases: `openId` → `OPEN_ID`, `authInitiated` → `AUTH_INITIATED`, `none` → `NONE`. `safeEnumValueOf<T>` applies it and returns null on `IllegalArgumentException`.

**This is why enum value names are part of the public contract** and are recorded in `api/dart-surface.txt`: renaming a Dart enum value changes the string sent over the channel, which changes (or breaks) the native enum lookup. iOS does not use this scheme — it matches lowercased literals instead, so the two platforms fail differently on an unknown value.

## §9 Platform asymmetry summary

| Capability | Android | iOS |
|---|---|---|
| Phone/email/channel auth, onetap, sessions, MFA, user-auth events | ✅ | ✅ |
| TrueCaller | ✅ | ❌ Dart-guarded |
| WhatsApp-installed check | ✅ | ❌ Dart-guarded |
| `startInBackground` | ✅ | ❌ Dart-guarded |
| SIM binding (3 methods) | ✅ | ❌ Dart-guarded |
| `closeDialogIfOpen` | ✅ | ❌ Dart-guarded |
| `OTP_AUTO_READ`, `AUTO_FLOW_ACTION` response types | ✅ | ❌ never emitted |
| `deviceFingerprintMode` in `startOnetap` | ✅ | ❌ dropped (§15.8) |
| `commitResponse` awaitable | ❌ hangs (§15.2) | ✅ |
| Unknown channel method | `notImplemented()` | ❌ hangs (§15.3) |
| `setDevLogging(false)` disables logging | ✅ | ❌ (§15.4) |

## §10 Networking & telemetry

**None in this plugin.** No HTTP client, no socket, no endpoint, no event push. All networking and all telemetry originate in the native SDKs — see android-full's and ios-headless's guides for endpoints, retry policy, and the event catalog.

The single exception is §6.5, where the Android bridge emits one telemetry event (`AUTH_FAILED` with `error: truecaller_init_failed`) through `OtplessSDK.userAuthEvent` on TrueCaller init failure. That is the only event this repo originates.

## §11 Data collection & logging

### §11.1 Collection

**The plugin collects nothing.** Device intelligence, telephony info, and app info are gathered by the native SDKs. `deviceFingerprintMode` merely forwards a merchant preference.

### §11.2 What the plugin logs — a live privacy defect

`utility.kt`'s `MethodCall.parseJsonArg()` executes:

```kotlin
Log.d(Tag, "arg: $jsonString")
```

`jsonString` is the **entire request payload** — which for `start` contains the merchant's end-user **phone number**, and on an OTP-verification call the **OTP itself**. This is:

- **unconditional** — not gated on `setDevLogging`, which only sets `OtplessSDK.devLogging` on the native SDK and has no effect on this line;
- present in **release** builds, since `Log.d` is not stripped by default and the plugin ships un-minified as source.

This violates constitution article 3 ("No PII in logs, ever"). Recorded as §15.9. `parseJsonArg` also logs on the malformed/absent paths, and `WhatsAppHandler` has a stray `print(newUrl)` (dead code, §15.11).

## §12 Persistence

**None in this plugin.** No `SharedPreferences`, no `UserDefaults`, no keychain, no files. Session tokens are held by the native `OtplessSessionManager`; the plugin only relays `{isActive, jwtToken}`.

The only in-memory state:
- Dart: `_callback` (the response callback).
- Kotlin: `channel`, `context`, `activity` (`WeakReference<FragmentActivity>`), `otplessJob`.
- Swift: `otplessTask`, plus `ChannelManager.shared`'s channel reference.

## §13 Build & toolchain

| | Value |
|---|---|
| Plugin version | **`pubspec.yaml` only** — the podspec derives it at parse time; the gate fails on a literal (§15.10) |
| Dart / Flutter floor | `sdk: ">=2.15.0 <4.0.0"`, `flutter: ">=2.5.0"` |
| Runtime deps | `flutter`, `plugin_platform_interface: ^2.0.2` — that's all, by design |
| Android | `compileSdkVersion 36`, `minSdkVersion 21`, Kotlin `2.0.21`, Java 1.8, namespace `com.otpless.headlessflutter` |
| Android native pin | `io.github.otpless-tech:otpless-headless-sdk:0.9.0` (exact) |
| iOS | `deployment_target 13.0`, Swift 5.5–5.9 |
| iOS native pin | `OtplessBM/Core 2.3.2` (exact) |

Consumer-side floor imposed by the 0.9.0 pin: **AGP 8.9.1+ and `compileSdkVersion` 36+**. That is a breaking requirement for merchants and is why 2.0.0 was a major bump.

Pins are **exact, never ranges** (constitution article 5). Bumping either is merchant-visible — see the **bump-native-sdk** skill. Note `0.9.0` is on Maven Central but carries **no git tag** upstream and is still filed under `## Unreleased` in android-full's changelog (hub `PARITY.md` C13).

The plugin does **not** support Swift Package Manager; `flutter build ios` warns about this and it will become an error in a future Flutter release.

## §14 Testing

### §14.1 What is verifiable, and where

| Layer | Proven by |
|---|---|
| Dart marshalling, guards, decoding | `flutter test` (fake channel) |
| A native handler **exists** for every Dart call | `scripts/docs-verify.sh` check 3 |
| Kotlin bridge **compiles** against the pinned SDK | `make example-android` |
| Swift bridge **compiles** against the pinned SDK | `make example-ios` |
| Actual auth behavior | manual run of `example/` on a device |

`flutter test` loads **no** Kotlin and **no** Swift. A bridge change with green Dart tests is unverified — see the **verify** skill.

### §14.2 Current coverage is near zero, and one test passes for the wrong reason

`test/` contains two tests: that `OtplessFlutterPlatform.instance` defaults to `MethodChannelOtplessFlutter`, and a `getPlatformVersion` test.

The second **replaces `OtplessFlutterPlatform.instance` with a mock** returning `'42'` and asserts it comes back. It therefore proves nothing about production: in production `getPlatformVersion()` throws (§15.1). This is the canonical example of a test that passes for the wrong reason — see the **add-tests** skill.

No test covers any of the 19 real channel methods.

## §15 Quirks & known defects

Verified against source at 2.0.0. Each is recorded in `CHANGELOG.md` under `## Unreleased` → "Known issues". **None is fixed** — they are documented so nobody rediscovers them or copies the pattern.

**§15.1 `getPlatformVersion()` always throws.** `MethodChannelOtplessFlutter` never overrides it and no native handler exists for a `getPlatformVersion` channel method, so it reaches `OtplessFlutterPlatform.getPlatformVersion()` → `UnimplementedError`. It is public API. Its test only passes via a mock (§14.2).

**§15.2 `commitResponse` never completes on Android.** The Kotlin handler calls `OtplessSDK.commit(...)` and returns without `result.success(...)`. iOS calls `result(nil)`. `await otpless.commitResponse(r)` therefore hangs forever on Android. The README's non-awaiting usage masks it, but every response leaks a pending `Future`.

**§15.3 iOS hangs on an unknown channel method.** `default: return` never calls `result`. Android returns `notImplemented()`. Any future Dart-side typo becomes an un-diagnosable hang on iOS only.

**§15.4 `setDevLogging(false)` cannot disable iOS logging.** The Swift handler installs the logger delegate only `if isEnabled` and never removes it, so logging survives the "off" call for the process lifetime.

**§15.5 A declared `EventChannel` is unused.** `MethodChannelOtplessFlutter.eventChannel = EventChannel('otpless_callback_event')` is never listened to. Responses arrive over the **method** channel via `setMethodCallHandler`. The field is public surface (it appears in the golden) and is misleading when writing tests — mock the method channel, not the event channel.

**§15.6 `cleanup` is unreachable.** Both natives implement it; no Dart API calls it. So a merchant cannot cancel in-flight work or release SDK resources. This is why `docs-verify.sh` warns (rather than fails) on natively-handled-but-uncalled methods — that state is also the *safe* intermediate step when removing a method.

**§15.7 The Dart response callback is force-unwrapped.** `_setEventChannel`'s handler calls `_callback!(result)`. `initialize` registers the native callback, so `SDK_READY` can arrive before the merchant calls `setResponseCallback`/`start` — at which point this throws inside the platform message handler.

**§15.8 iOS drops `deviceFingerprintMode` in `startOnetap`.** Dart sends it, Kotlin parses it, Swift constructs `OtplessAuthCofig(isForeground:otp:tid:)` without it. (Note the upstream type's spelling — `OtplessAuthCofig` — is a typo in the iOS SDK, not here.)

**§15.9 The Android bridge logs the full request payload, including phone number and OTP.** See §11.2. Unconditional, ungated, present in release builds.

**§15.10 Two dead channel arguments.**
- `initialize`'s `timeout` (default `30.0`) is sent by Dart and read by **neither** native — a documented parameter with no effect.
- Kotlin's `initialize` reads `loginUri`, which Dart **never sends** — so the deep-link login URI cannot be configured from Flutter at all, despite the native SDK supporting it.

**§15.11 Dead code.** `ios/Classes/WhatsAppHandler.swift` and `ios/Classes/Strings.swift` are unreferenced legacy from the pre-headless plugin (2022 headers, `otpless_flutter` file comments). `WhatsAppHandler` also contains a force-unwrap (`addingPercentEncoding(...)!`) and a `print` of a URL. `OtplessSimEventListener` in `lib/` is likewise declared and never used. All ship in the published package.

**§15.12 iOS force-unwraps channel arguments.** `start`, `initialize`, `startOnetap`, `setDevLogging` and `setMfaEnabled` use `call.arguments as! [String: Any]`, and `start`/`startOnetap` additionally `args["arg"] as! String`. A malformed call **crashes the host app** rather than returning an error. Do not copy this shape (constitution article 2).

**§15.13 Android throws out of `onMethodCall` on a malformed `arg`.** `parseJsonArg()` throws `Exception("json argument not provided")` when `arg` is missing or unparseable. For `start` this happens *after* `result.success(null)`, so the Dart side resolves normally while the exception propagates out of the plugin on the platform thread.

**§15.14 `Otpless` bypasses the platform interface.** It constructs its own `MethodChannelOtplessFlutter` field rather than using `OtplessFlutterPlatform.instance`, so overriding `instance` (the documented test seam, and the mechanism `plugin_platform_interface` exists for) affects only `getPlatformVersion`.

**§15.15 Status-code sentinels disagree across platforms.** A non-integer `statusCode` on commit becomes `-1000` on Android; a missing one becomes `-25000` on iOS. An unknown `responseType` yields `null` (Android, commit skipped) versus `.FAILED` (iOS).
