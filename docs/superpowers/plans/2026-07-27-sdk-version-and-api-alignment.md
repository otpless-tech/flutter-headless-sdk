# SDK Version Bump + Public API Alignment — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bump Otpless native SDKs (Android `0.6.6 → 0.9.0`, iOS `2.0.8 → 2.3.2`) and expand/rename the Flutter plugin's public API to match the new native surface.

**Architecture:** Three-layer plugin. Dart public API (`lib/otpless_flutter.dart`) → `MethodChannel('otpless_headless_flutter')` → Kotlin (`OtplessFlutterHeadless.kt`) / Swift (`SwiftOtplessFlutterHeadless.swift`) → native SDKs. Existing pattern preserved: `Map<String, dynamic>` for `start()` requests, `dynamic` for callback responses, single method channel with `otpless_callback_event` reverse invocation for responses.

**Tech Stack:** Dart 2.15+ / Flutter 2.5+, Kotlin 1.6.10 + `androidx.lifecycleScope` coroutines, Swift 5.5+ + `Task { @MainActor }` isolation, `OtplessBM/Core 2.3.2`, `io.github.otpless-tech:otpless-headless-sdk:0.9.0`.

## Global Constraints

- Plugin version target: **2.0.0** (major bump). Never publish under `1.x` — the rename and new response types are user-visible breakages.
- Android artifact: `io.github.otpless-tech:otpless-headless-sdk:0.9.0` (exact).
- iOS pod: `OtplessBM/Core`, version `2.3.2` (exact).
- Channel name unchanged: `otpless_headless_flutter`.
- Channel event name unchanged: `otpless_callback_event`.
- Do **not** introduce typed request/response Dart models — request stays `Map<String, dynamic>`, response stays `dynamic`. Only `DeviceFingerprintMode` becomes a Dart enum.
- The Dart-side JSON key for template ID is **`tid`** (matches iOS native + existing Kotlin parser). Never use `templateId`.
- `locale` is **not** added as a Dart key in this release.
- `OtplessPhoneHint`, iOS `handleDeeplink`, iOS `registerFBApp`, iOS `authorizeViaPasskey`, iOS `isOtplessDeeplink` are **not** exposed through Dart. They are documented as client-side native integration.
- No automated tests are added — spec §2 non-goal. Verification happens through `flutter analyze`, existing `flutter test`, and manual example-app runs.
- The design spec at `docs/superpowers/specs/2026-07-27-sdk-version-and-api-alignment-design.md` is the source of truth. Cross-check any ambiguous decision against it before making a call.
- Commit after every task using conventional commit style: `feat:` / `fix:` / `refactor:` / `docs:` / `chore:`.

---

### Task 1: Bump native SDK versions and plugin version

**Files:**
- Modify: `pubspec.yaml:3`
- Modify: `android/build.gradle:50`
- Modify: `ios/otpless_headless_flutter.podspec:18`

**Interfaces:**
- Consumes: nothing
- Produces: three pinned version strings that every downstream task assumes.

- [ ] **Step 1: Update `pubspec.yaml` version**

Change `pubspec.yaml:3` from:

```yaml
version: 1.1.1
```

to:

```yaml
version: 2.0.0
```

- [ ] **Step 2: Update Android AAR pin**

Change `android/build.gradle:50` from:

```groovy
    implementation ("io.github.otpless-tech:otpless-headless-sdk:0.6.6")
```

to:

```groovy
    implementation ("io.github.otpless-tech:otpless-headless-sdk:0.9.0")
```

- [ ] **Step 3: Update iOS pod pin**

Change `ios/otpless_headless_flutter.podspec:18` from:

```ruby
  s.dependency 'OtplessBM/Core', '2.0.8'
```

to:

```ruby
  s.dependency 'OtplessBM/Core', '2.3.2'
```

- [ ] **Step 4: Refresh Flutter deps and confirm resolution**

Run: `flutter pub get`
Expected: exits 0. Ignore lockfile changes — the example app pins are separate.

- [ ] **Step 5: Refresh example app deps**

Run: `cd example && flutter pub get && cd -`
Expected: exits 0.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml android/build.gradle ios/otpless_headless_flutter.podspec pubspec.lock example/pubspec.lock
git commit -m "chore: bump plugin to 2.0.0 and native SDKs (android 0.9.0, ios 2.3.2)"
```

---

### Task 2: Extend Dart models (DeviceFingerprintMode + OtplessAuthConfig)

**Files:**
- Modify: `lib/models.dart:131-145` (extend `OtplessAuthConfig`)
- Modify: `lib/models.dart` (append new enum near line 149)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum DeviceFingerprintMode { none, async, sync }` — imported by later Dart tasks and serialized as `mode.name` (`"none"` / `"async"` / `"sync"`) across the channel.
  - `OtplessAuthConfig` gains an optional named parameter `DeviceFingerprintMode deviceFingerprintMode = DeviceFingerprintMode.none`. `toMap()` includes the key `deviceFingerprintMode` with `mode.name` (always present, defaults to `"none"`).

- [ ] **Step 1: Add `DeviceFingerprintMode` enum**

At the end of `lib/models.dart`, after the `ProviderType` enum (currently line 149), append:

```dart
enum DeviceFingerprintMode { none, async, sync }
```

- [ ] **Step 2: Extend `OtplessAuthConfig` with `deviceFingerprintMode`**

Replace `lib/models.dart:131-145` (the entire `class OtplessAuthConfig { ... }` block) with:

```dart
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
```

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/models.dart`
Expected: `No issues found!`

- [ ] **Step 4: Run existing tests**

Run: `flutter test`
Expected: PASS. Only the two existing tests run; neither touches models.

- [ ] **Step 5: Commit**

```bash
git add lib/models.dart
git commit -m "feat(dart): add DeviceFingerprintMode enum and extend OtplessAuthConfig"
```

---

### Task 3: Harden Kotlin `utility.kt` — parser + new request keys

**Files:**
- Modify: `android/src/main/kotlin/com/otpless/headlessflutter/utility.kt` (imports + `parseJsonToOtplessRequest` at `:28-69` + `parseToOtplessAuthConfig` at `:71-74`)

**Interfaces:**
- Consumes: existing `safeEnumValueOf<T>` and `fromDartEnumStyleToKotlin` in the same file.
- Produces:
  - `parseJsonToOtplessRequest(json: JSONObject): OtplessRequest` — now reads five new keys from `json`: `code`, `extras`, `requestId`, `deviceFingerprintMode`, and continues to read `tid`. Rejects unknown channels via `OtplessChannelType.fromString(...)`. Skips empty-string optional setters.
  - `parseToOtplessAuthConfig(json: JSONObject): OtplessAuthConfig` — now reads `deviceFingerprintMode` and passes it to the `OtplessAuthConfig` constructor.

- [ ] **Step 1: Add missing imports**

At the top of `android/src/main/kotlin/com/otpless/headlessflutter/utility.kt`, in the import block starting at line 14, add:

```kotlin
import com.otpless.v2.android.sdk.dto.DeviceFingerprintMode
```

Keep it grouped with the other `com.otpless.v2.android.sdk.dto.*` imports (lines 14-18).

- [ ] **Step 2: Rewrite `parseJsonToOtplessRequest`**

Replace `utility.kt:28-69` (the entire `parseJsonToOtplessRequest` function) with:

```kotlin
/// parse json request into OtplessRequest model class
/// json serialization is not used because of enum parsing (channel) and conversion
internal fun parseJsonToOtplessRequest(json: JSONObject): OtplessRequest {
    val otplessRequest = OtplessRequest()

    val phone = json.optString("phone")
    val email = json.optString("email")
    val channelType = json.optString("channelType")

    when {
        phone.isNotEmpty() -> {
            val countryCode = json.optString("countryCode")
            otplessRequest.setPhoneNumber(number = phone, countryCode = countryCode)
        }
        email.isNotEmpty() -> otplessRequest.setEmail(email)
        channelType.isNotEmpty() -> otplessRequest.setChannelType(OtplessChannelType.fromString(channelType))
    }

    json.optString("otp").takeIf { it.isNotEmpty() }?.let { otplessRequest.setOtp(it) }
    json.optString("code").takeIf { it.isNotEmpty() }?.let { otplessRequest.setCode(it) }
    json.optString("otpLength").takeIf { it.isNotEmpty() }?.let { otplessRequest.setOtpLength(it) }
    json.optString("expiry").takeIf { it.isNotEmpty() }?.let { otplessRequest.setExpiry(it) }
    json.optString("tid").takeIf { it.isNotEmpty() }?.let { otplessRequest.setTemplateId(it) }
    json.optString("deliveryChannel").takeIf { it.isNotEmpty() }?.let { otplessRequest.setDeliveryChannel(it) }
    json.optString("requestId").takeIf { it.isNotEmpty() }?.let { otplessRequest.requestId = it }

    json.optJSONObject("extras")?.let { extrasJson ->
        val map = mutableMapOf<String, String>()
        val keys = extrasJson.keys()
        for (key in keys) {
            val value = extrasJson.optString(key)
            if (value.isNotEmpty()) map[key] = value
        }
        if (map.isNotEmpty()) otplessRequest.setExtras(map)
    }

    json.optString("deviceFingerprintMode").takeIf { it.isNotEmpty() }?.let { modeStr ->
        safeEnumValueOf<DeviceFingerprintMode>(modeStr)?.let { mode ->
            otplessRequest.deviceFingerprintMode = mode
        }
    }

    return otplessRequest
}
```

- [ ] **Step 3: Rewrite `parseToOtplessAuthConfig`**

Replace `utility.kt:71-74` (the `parseToOtplessAuthConfig` function) with:

```kotlin
internal fun parseToOtplessAuthConfig(json: JSONObject): OtplessAuthConfig {
    val isForeground = json.optBoolean("isForeground", false)
    val otp = json.optString("otp")
    val tid = json.optString("tid").takeIf { it.isNotEmpty() }
    val fingerprintMode = json.optString("deviceFingerprintMode")
        .takeIf { it.isNotEmpty() }
        ?.let { safeEnumValueOf<DeviceFingerprintMode>(it) }
        ?: DeviceFingerprintMode.NONE
    return OtplessAuthConfig(isForeground, otp, tid, fingerprintMode)
}
```

- [ ] **Step 4: Try compiling the plugin's Android side via the example app**

Run: `cd example && flutter build apk --debug --target-platform android-arm64 2>&1 | tail -40 && cd -`
Expected: build succeeds. Any Kotlin compile error indicates a signature mismatch — inspect and fix before committing.

If the build reports `Unresolved reference: fromString` on `OtplessChannelType`, verify the 0.9.0 dependency actually resolved (`ls ~/.gradle/caches/modules-2/files-2.1/io.github.otpless-tech/otpless-headless-sdk/0.9.0` should be non-empty). If empty, re-run `flutter pub get` and retry.

- [ ] **Step 5: Commit**

```bash
git add android/src/main/kotlin/com/otpless/headlessflutter/utility.kt
git commit -m "refactor(android): harden request parser and add new keys (code/extras/requestId/deviceFingerprintMode)"
```

---

### Task 4: Update Kotlin `OtplessFlutterHeadless.kt` — rename + new channel cases

**Files:**
- Modify: `android/src/main/kotlin/com/otpless/headlessflutter/OtplessFlutterHeadless.kt` (imports, `onMethodCall` switch at `:48-137`, add helper functions)

**Interfaces:**
- Consumes: `parseJsonToOtplessRequest`, `parseToOtplessAuthConfig`, `safeEnumValueOf<DeviceFingerprintMode>` from `utility.kt` (Task 3).
- Produces: The following channel method names must be present in the `when` switch (used by Task 6):
  - `"startOnetap"` (renamed from `startBackground`)
  - `"startInBackground"`
  - `"setDeviceFingerprintMode"`
  - `"setMfaEnabled"`
  - `"initSession"`
  - `"getActiveSession"`
  - `"logoutSession"`
  - `"checkSimBindingStatus"`
  - `"clearSimBinding"`
  - `"setSimBindingEnabled"`
  - `"closeDialogIfOpen"` (already exists but result acknowledgement is added)

- [ ] **Step 1: Add imports**

At the top of `OtplessFlutterHeadless.kt`, in the import block (currently lines 9-13), add:

```kotlin
import com.otpless.v2.android.sdk.dto.DeviceFingerprintMode
import com.otpless.v2.android.sdk.session.OtplessSessionManager
import com.otpless.v2.android.sdk.session.OtplessSessionState
```

Group them with the existing `com.otpless.v2.android.sdk.*` imports.

- [ ] **Step 2: Add plugin-level `defaultFingerprintMode` field**

Right after the `private var otplessJob: Job? = null` declaration at `OtplessFlutterHeadless.kt:40`, add:

```kotlin
    private var defaultFingerprintMode: DeviceFingerprintMode = DeviceFingerprintMode.NONE
```

- [ ] **Step 3: Rename `"startBackground"` case to `"startOnetap"` and acknowledge result**

Replace `OtplessFlutterHeadless.kt:123-125` (the entire `"startBackground" -> { ... }` case) with:

```kotlin
            "startOnetap" -> {
                startOnetap(call.parseJsonArg(), result)
            }
```

Then replace the `private fun startBackground(json: JSONObject, result: Result)` at `:158-165` with:

```kotlin
    private fun startOnetap(json: JSONObject, result: Result) {
        otplessJob?.cancel()
        activity.get()?.let { activity ->
            otplessJob = activity.lifecycleScope.launch(Dispatchers.IO) {
                val config = parseToOtplessAuthConfig(json).applyDefaultFingerprintMode()
                result.success(OtplessSDK.start(config))
            }
        } ?: result.success(false)
    }
```

- [ ] **Step 4: Add helper extensions for applying the plugin-level default fingerprint mode**

Immediately below the `private fun startOnetap(...)` you just added, insert:

```kotlin
    private fun OtplessRequest.applyDefaultFingerprintMode(): OtplessRequest {
        if (this.deviceFingerprintMode == DeviceFingerprintMode.NONE && defaultFingerprintMode != DeviceFingerprintMode.NONE) {
            this.deviceFingerprintMode = defaultFingerprintMode
        }
        return this
    }

    private fun OtplessAuthConfig.applyDefaultFingerprintMode(): OtplessAuthConfig {
        return if (this.deviceFingerprintMode == DeviceFingerprintMode.NONE && defaultFingerprintMode != DeviceFingerprintMode.NONE) {
            this.copy(deviceFingerprintMode = defaultFingerprintMode)
        } else this
    }
```

Add the required import at the top:

```kotlin
import com.otpless.v2.android.sdk.dto.OtplessRequest
```

- [ ] **Step 5: Replace `start` body — apply default fingerprint mode and remove now-missing `hasOtp()` call**

Android SDK 0.9.0 removed the `hasOtp()` method on `OtplessRequest`. The existing plugin at `OtplessFlutterHeadless.kt:146` calls it, so the plugin will not compile against 0.9.0 without this replacement. Derive the OTP-verification flag from the JSON directly (mirrors the iOS behavior at `SwiftOtplessFlutterHeadless.swift:70`).

Replace the body of `private fun start(json: JSONObject)` at `:143-156` with:

```kotlin
    private fun start(json: JSONObject) {
        val fa = activity.get() ?: return
        val request = parseJsonToOtplessRequest(json).applyDefaultFingerprintMode()
        val isOtpVerification = json.optString("otp").isNotEmpty()
        if (!isOtpVerification) {
            otplessJob?.cancel()
        }
        val newJob = fa.lifecycleScope.launch(Dispatchers.IO) {
            OtplessSDK.start(request = request, this@OtplessFlutterHeadless::onOtplessResponseCallback)
        }
        if (!isOtpVerification) {
            otplessJob = newJob
        }
    }
```

- [ ] **Step 6: Add `startInBackground` case + helper**

Insert this case in the `onMethodCall` switch, right below the `"startOnetap"` case:

```kotlin
            "startInBackground" -> {
                result.success(null)
                startInBackground(call.parseJsonArg())
            }
```

And add this helper method right below `private fun startOnetap`:

```kotlin
    private fun startInBackground(json: JSONObject) {
        val fa = activity.get() ?: return
        val request = parseJsonToOtplessRequest(json).applyDefaultFingerprintMode()
        otplessJob?.cancel()
        otplessJob = fa.lifecycleScope.launch(Dispatchers.IO) {
            OtplessSDK.startInBackground(request = request, this@OtplessFlutterHeadless::onOtplessResponseCallback)
        }
    }
```

- [ ] **Step 7: Add `setDeviceFingerprintMode` case**

Insert this case in the `onMethodCall` switch, before the `else -> { result.notImplemented() }`:

```kotlin
            "setDeviceFingerprintMode" -> {
                val mode = safeEnumValueOf<DeviceFingerprintMode>(call.argument<String>("mode"))
                defaultFingerprintMode = mode ?: DeviceFingerprintMode.NONE
                result.success(null)
            }
```

- [ ] **Step 8: Add `setMfaEnabled` case**

Insert:

```kotlin
            "setMfaEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                OtplessSDK.isMfaEnabled = enabled
                result.success(null)
            }
```

- [ ] **Step 9: Add `initSession` case**

Insert:

```kotlin
            "initSession" -> {
                val appId = call.argument<String>("appId") ?: return kotlin.run {
                    result.error("0", "appId is required for initSession", null)
                }
                val mActivity = activity.get() ?: return kotlin.run {
                    result.error("0", "initSession called before activity is attached", null)
                }
                mActivity.lifecycleScope.launch(Dispatchers.IO) {
                    OtplessSessionManager.init(context, appId)
                    result.success(null)
                }
            }
```

- [ ] **Step 10: Add `getActiveSession` case**

Insert:

```kotlin
            "getActiveSession" -> {
                val mActivity = activity.get() ?: return kotlin.run {
                    result.success(mapOf("isActive" to false))
                }
                mActivity.lifecycleScope.launch(Dispatchers.IO) {
                    val state = OtplessSessionManager.getActiveSession()
                    val map: Map<String, Any?> = when (state) {
                        is OtplessSessionState.Active -> mapOf("isActive" to true, "jwtToken" to state.jwtToken)
                        is OtplessSessionState.Inactive -> mapOf("isActive" to false)
                    }
                    result.success(map)
                }
            }
```

- [ ] **Step 11: Add `logoutSession` case**

Insert:

```kotlin
            "logoutSession" -> {
                val mActivity = activity.get() ?: return kotlin.run { result.success(null) }
                mActivity.lifecycleScope.launch(Dispatchers.IO) {
                    OtplessSessionManager.logout()
                    result.success(null)
                }
            }
```

- [ ] **Step 12: Add SIM binding cases**

Insert three cases:

```kotlin
            "checkSimBindingStatus" -> {
                val mActivity = activity.get() ?: return kotlin.run { result.success(false) }
                mActivity.lifecycleScope.launch(Dispatchers.IO) {
                    result.success(OtplessSDK.checkSimBindingStatus(context))
                }
            }

            "clearSimBinding" -> {
                val mActivity = activity.get() ?: return kotlin.run { result.success(null) }
                mActivity.lifecycleScope.launch(Dispatchers.IO) {
                    OtplessSDK.clearSimBinding(context)
                    result.success(null)
                }
            }

            "setSimBindingEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                OtplessSDK.isSimBindingEnabled = enabled
                result.success(null)
            }
```

- [ ] **Step 13: Send result acknowledgement for `closeDialogIfOpen`**

Replace `OtplessFlutterHeadless.kt:127-129` (the `"closeDialogIfOpen" -> { ... }` case) with:

```kotlin
            "closeDialogIfOpen" -> {
                OtplessSDK.closeDialogIfOpen()
                result.success(null)
            }
```

- [ ] **Step 14: Leave existing `"userAuthEvent"` case in place**

Verify the case `"userAuthEvent" -> sendUserAuthEvent(call, result)` still exists at the end of the switch. The channel key stays as `"userAuthEvent"` (unchanged from 1.x); Task 6 Step 3 will remove Dart's `Platform.isAndroid` guard on the Dart side and fix the `providerInfo` inversion bug, but no Kotlin case rename is required.

- [ ] **Step 15: Compile via example app**

Run: `cd example && flutter build apk --debug --target-platform android-arm64 2>&1 | tail -80 && cd -`
Expected: build succeeds.

Common failure and fix:
- `Unresolved reference: OtplessSessionManager` → verify import at Step 1 is present and points to `com.otpless.v2.android.sdk.session.OtplessSessionManager`. If the artifact truly doesn't ship that class at 0.9.0, run `grep -r "public.*object OtplessSessionManager" ~/.gradle/caches/modules-2/files-2.1/io.github.otpless-tech/otpless-headless-sdk/0.9.0/` — if not found, this task cannot proceed and the SDK version needs re-verification.

- [ ] **Step 16: Commit**

```bash
git add android/src/main/kotlin/com/otpless/headlessflutter/OtplessFlutterHeadless.kt
git commit -m "feat(android): rename startBackground->startOnetap and add session/MFA/SIM-binding/fingerprint methods"
```

---

### Task 5: Update Swift bridge — rename + fill missing cases + add new cases

**Files:**
- Modify: `ios/Classes/SwiftOtplessFlutterHeadless.swift` (`handleOnMainThread` switch at `:27-64`, `createOtplessRequest` at `:100-133`, new helper for session state map)

**Interfaces:**
- Consumes: existing `rootViewController()` helper at `SwiftOtplessFlutterHeadless.swift:136`.
- Produces: the same set of case names as Task 4 (`startOnetap`, `startInBackground`, `setDeviceFingerprintMode`, `setMfaEnabled`, `initSession`, `getActiveSession`, `logoutSession`, `checkSimBindingStatus`, `clearSimBinding`, `setSimBindingEnabled`, `closeDialogIfOpen`, `isWhatsAppInstalled`, `initTrueCaller`, `sendUserAuthEvent`). Android-only ones return `result(false)` / `result(nil)`.

- [ ] **Step 1: Import session manager**

Verify `import OtplessBM` is present at `SwiftOtplessFlutterHeadless.swift:3` (it already is). No additional import needed since `OtplessSessionManager`, `OtplessSessionState`, `DeviceFingerprintMode`, and `OtplessAuthCofig` are all part of `OtplessBM`.

- [ ] **Step 2: Add cross-platform new cases in the `switch`**

Insert these cases inside `handleOnMainThread`'s switch, immediately after `case "isSdkReady":` (line 60-61). Each block replaces the pattern of falling through to `default: return`.

```swift
        case "setDeviceFingerprintMode":
            let args = call.arguments as! [String: Any]
            let modeStr = (args["mode"] as? String)?.uppercased() ?? "NONE"
            let mode: DeviceFingerprintMode
            switch modeStr {
            case "ASYNC": mode = .ASYNC
            case "SYNC":  mode = .SYNC
            default:      mode = .NONE
            }
            Otpless.shared.setDeviceFingerprintMode(mode)
            result(nil)
        case "setMfaEnabled":
            let args = call.arguments as! [String: Any]
            let enabled = (args["enabled"] as? Bool) ?? false
            Otpless.shared.setMfaEnabled(enabled)
            result(nil)
        case "initSession":
            let args = call.arguments as! [String: Any]
            let appId = args["appId"] as? String ?? ""
            Task {
                await OtplessSessionManager.shared.initialize(appId: appId)
                DispatchQueue.main.async { result(nil) }
            }
        case "getActiveSession":
            Task {
                let state = await OtplessSessionManager.shared.getActiveSession()
                let map: [String: Any?]
                switch state {
                case .active(let jwt): map = ["isActive": true, "jwtToken": jwt]
                case .inactive:        map = ["isActive": false]
                }
                DispatchQueue.main.async { result(map) }
            }
        case "logoutSession":
            Task {
                await OtplessSessionManager.shared.logout()
                DispatchQueue.main.async { result(nil) }
            }
```

- [ ] **Step 3: Add the new `startOnetap` case + rename from prior `startBackground`**

Insert immediately below the `logoutSession` case:

```swift
        case "startOnetap":
            let args = call.arguments as! [String: Any]
            let jsonString = args["arg"] as! String
            guard let data = jsonString.data(using: .utf8),
                  let dict = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
                result(false)
                return
            }
            guard let rootVC = Self.rootViewController() else {
                result(false)
                return
            }
            let isForeground = (dict["isForeground"] as? Bool) ?? false
            let otp = dict["otp"] as? String
            let tid = dict["tid"] as? String
            let config = OtplessAuthCofig(isForeground: isForeground, otp: otp, tid: tid)
            Task { @MainActor in
                let ok = await Otpless.shared.startAuth(parent: rootVC, config: config)
                DispatchQueue.main.async { result(ok) }
            }
```

Note: iOS's `OtplessAuthCofig` has no `deviceFingerprintMode` slot — the Dart-side value is silently dropped on iOS, consistent with spec §6.2.

- [ ] **Step 4: Fill remaining missing switch cases (Android-only stubs + `userAuthEvent`)**

Insert immediately below the `startOnetap` case. Note the case name for the auth-event handler is `"userAuthEvent"` — matches the current Kotlin case name; Task 6 Step 3 keeps the Dart channel key at the same value.

```swift
        case "isWhatsAppInstalled":
            result(false)
        case "initTrueCaller":
            result(false)
        case "startInBackground":
            result(nil)
        case "userAuthEvent":
            let args = (call.arguments as? [String: Any]) ?? [:]
            let eventStr = (args["event"] as? String)?.lowercased() ?? ""
            let fallback = (args["fallback"] as? Bool) ?? false
            let providerTypeStr = (args["providerType"] as? String)?.lowercased() ?? ""
            let event: AuthEvent
            switch eventStr {
            case "authinitiated": event = .AUTH_INITIATED
            case "authsuccess":   event = .AUTH_SUCCESS
            case "authfailed":    event = .AUTH_FAILED
            default:
                result(false)
                return
            }
            let providerType: ProviderType = (providerTypeStr == "otpless") ? .OTPLESS : .CLIENT
            var providerInfo: [String: String] = [:]
            if let raw = args["providerInfo"] as? String,
               let data = raw.data(using: .utf8),
               let dict = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] {
                for (k, v) in dict { providerInfo[k] = "\(v)" }
            }
            Otpless.shared.userAuthEvent(event: event, fallback: fallback, providerType: providerType, providerInfo: providerInfo)
            result(true)
        case "checkSimBindingStatus":
            result(false)
        case "clearSimBinding":
            result(nil)
        case "setSimBindingEnabled":
            result(nil)
        case "closeDialogIfOpen":
            result(nil)
```

- [ ] **Step 5: Extend `createOtplessRequest` to read the four new keys**

Replace `SwiftOtplessFlutterHeadless.swift:100-133` (the entire `createOtplessRequest(args:)` function) with:

```swift
    private func createOtplessRequest(args: [String: Any]) -> OtplessRequest {
        let otplessRequest = OtplessRequest()
        
        if let phone = args["phone"] as? String, !phone.isEmpty,
           let countryCode = args["countryCode"] as? String {
            otplessRequest.set(phoneNumber: phone, withCountryCode: countryCode)
        } else if let email = args["email"] as? String, !email.isEmpty {
            otplessRequest.set(email: email)
        } else if let channelType = args["channelType"] as? String, !channelType.isEmpty {
            otplessRequest.set(channelType: OtplessChannelType.fromString(channelType.uppercased()))
        }
        
        if let otp = args["otp"] as? String, !otp.isEmpty { otplessRequest.set(otp: otp) }
        if let code = args["code"] as? String, !code.isEmpty { otplessRequest.set(code: code) }
        if let deliveryChannel = args["deliveryChannel"] as? String, !deliveryChannel.isEmpty {
            otplessRequest.set(deliveryChannelForTransaction: deliveryChannel.uppercased())
        }
        if let otpLength = args["otpLength"] as? String, !otpLength.isEmpty { otplessRequest.set(otpLength: otpLength) }
        if let expiry = args["expiry"] as? String, !expiry.isEmpty { otplessRequest.set(otpExpiry: expiry) }
        if let tid = args["tid"] as? String, !tid.isEmpty { otplessRequest.set(tid: tid) }
        if let requestId = args["requestId"] as? String, !requestId.isEmpty { otplessRequest.set(fromBackend: requestId) }
        
        if let extras = args["extras"] as? [String: String], !extras.isEmpty {
            otplessRequest.set(extras: extras)
        }
        
        if let modeStr = (args["deviceFingerprintMode"] as? String)?.uppercased() {
            switch modeStr {
            case "ASYNC": otplessRequest.set(deviceFingerprintMode: .ASYNC)
            case "SYNC":  otplessRequest.set(deviceFingerprintMode: .SYNC)
            case "NONE":  otplessRequest.set(deviceFingerprintMode: .NONE)
            default: break
            }
        }
        
        return otplessRequest
    }
```

Note: parameter type changed from `[String: String]` to `[String: Any]` so extras / booleans can pass through.

- [ ] **Step 6: Update the `"start"` case to pass `[String: Any]` and to no longer assume all values are strings**

Replace `SwiftOtplessFlutterHeadless.swift:29-35` (the `case "start":` block) with:

```swift
        case "start":
            let args = call.arguments as! [String: Any]
            let jsonString = args["arg"] as! String
            let data = jsonString.data(using: .utf8)!
            let arguments = (try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]) ?? [:]
            start(withDict: arguments)
            result(nil)
```

And update the private `start(withDict:)` signature at `SwiftOtplessFlutterHeadless.swift:67-84`:

```swift
    private func start(withDict dict: [String: Any]) {
        let otplessRequest = createOtplessRequest(args: dict)
        let isOtpVerification = (dict["otp"] as? String)?.isEmpty == false
        if !isOtpVerification {
            otplessTask?.cancel()
        }
        let newTask = Task(priority: .userInitiated) {
            await Otpless.shared.start(withRequest: otplessRequest)
        }
        if !isOtpVerification {
            otplessTask = newTask
        }
    }
```

- [ ] **Step 7: Try building the iOS side via the example app**

Run: `cd example && flutter build ios --debug --no-codesign 2>&1 | tail -50 && cd -`
Expected: build succeeds.

Common failure and fix:
- `Cannot find 'OtplessSessionManager' in scope` → confirm `pod install` picked up 2.3.2 (`cat example/ios/Podfile.lock | grep OtplessBM`). If it shows 2.0.8, run `cd example/ios && pod repo update && pod install && cd -` and retry.
- Enum-name mismatch (`.INIT` vs `.AUTH_INITIATED`) → open the OtplessBM headers via Xcode and adjust the Swift enum access to the exact case name.

- [ ] **Step 8: Commit**

```bash
git add ios/Classes/SwiftOtplessFlutterHeadless.swift
git commit -m "feat(ios): rename startBackground->startOnetap, fill missing switch cases, add session/MFA/fingerprint"
```

---

### Task 6: Update Dart method channel — rename, bug fix, new methods

**Files:**
- Modify: `lib/otpless_flutter_method_channel.dart` (rename `startBackground` → `startOnetap`; fix `providerInfo` inversion; add new methods)

**Interfaces:**
- Consumes: `MethodChannel('otpless_headless_flutter')` and channel method names from Task 4 / Task 5.
- Produces: methods called from `lib/otpless_flutter.dart` (Task 7):
  - `Future<bool> startOnetap(OtplessResultCallback callback, OtplessAuthConfig config)`
  - `Future<void> startInBackground(OtplessResultCallback callback, Map<String, dynamic> jsonObject)`
  - `Future<void> setDeviceFingerprintMode(DeviceFingerprintMode mode)`
  - `Future<void> setMfaEnabled(bool enabled)`
  - `Future<void> initSession(String appId)`
  - `Future<Map<String, dynamic>> getActiveSession()`
  - `Future<void> logoutSession()`
  - `Future<bool> checkSimBindingStatus()`
  - `Future<void> clearSimBinding()`
  - `Future<void> setSimBindingEnabled(bool enabled)`
  - `Future<void> closeDialogIfOpen()`
  - Existing `sendUserAuthEvent` is renamed to still be called `sendUserAuthEvent` but no longer platform-guards on iOS (iOS bridge now implements it) and has the bug fixed.

- [ ] **Step 1: Rename `startBackground` method + channel key**

Replace `lib/otpless_flutter_method_channel.dart:84-89` (the entire `startBackground` method) with:

```dart
  Future<bool> startOnetap(
      OtplessResultCallback callback, OtplessAuthConfig config) async {
    _callback = callback;
    return await methodChannel
        .invokeMethod("startOnetap", {'arg': json.encode(config.toMap())});
  }
```

Note that (a) the method is renamed, (b) the channel key changes to `"startOnetap"`, (c) the Android-only guard is removed since iOS now handles this case, and (d) `_callback = callback` is now set so responses flow back to the caller on both platforms.

- [ ] **Step 2: Add `startInBackground`**

Below the new `startOnetap`, add:

```dart
  Future<void> startInBackground(
      OtplessResultCallback callback, Map<String, dynamic> jsonObject) async {
    if (!Platform.isAndroid) return;
    _callback = callback;
    await methodChannel
        .invokeMethod("startInBackground", {'arg': json.encode(jsonObject)});
  }
```

- [ ] **Step 3: Fix `sendUserAuthEvent` bug and remove Android-only guard**

Replace `lib/otpless_flutter_method_channel.dart:91-101` (the entire `sendUserAuthEvent` method) with:

```dart
  Future<bool> sendUserAuthEvent(
      AuthEvent event, bool fallback, ProviderType providerType,
      {Map<String, dynamic>? providerInfo}) async {
    return await methodChannel.invokeMethod("userAuthEvent", {
      "event": event.name,
      "fallback": fallback,
      "providerType": providerType.name,
      if (providerInfo != null) "providerInfo": json.encode(providerInfo),
    });
  }
```

Note the two changes: (a) `Platform.isAndroid` guard removed (iOS now handles it), (b) the inversion bug `if (providerInfo == null)` → `if (providerInfo != null)` is fixed. The channel key stays as `"userAuthEvent"` to match the existing Kotlin case (no cross-file coordination needed).

- [ ] **Step 4: Add `setDeviceFingerprintMode`**

Add near the top of the class body (after `setDevLogging` at `:60-62`), taking care to import the model:

At the top of the file, extend the import at line 6:

```dart
import 'package:otpless_headless_flutter/models.dart';
```

(This import already exists — no change needed. Just verify.)

Then add the method:

```dart
  Future<void> setDeviceFingerprintMode(DeviceFingerprintMode mode) async {
    await methodChannel.invokeMethod("setDeviceFingerprintMode", {'mode': mode.name});
  }
```

- [ ] **Step 5: Add `setMfaEnabled`, session methods, and closeDialogIfOpen**

Add these methods below `setDeviceFingerprintMode`:

```dart
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
```

- [ ] **Step 6: Add SIM binding methods**

Add these three methods:

```dart
  Future<bool> checkSimBindingStatus() async {
    if (!Platform.isAndroid) return false;
    final ok = await methodChannel.invokeMethod("checkSimBindingStatus");
    return ok as bool;
  }

  Future<void> clearSimBinding() async {
    if (!Platform.isAndroid) return;
    await methodChannel.invokeMethod("clearSimBinding");
  }

  Future<void> setSimBindingEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    await methodChannel.invokeMethod("setSimBindingEnabled", {'enabled': enabled});
  }
```

- [ ] **Step 7: Run static analysis**

Run: `flutter analyze lib/`
Expected: `No issues found!`

- [ ] **Step 8: Run existing tests**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/otpless_flutter_method_channel.dart
git commit -m "feat(dart): expand method channel with new APIs, rename startBackground->startOnetap, fix providerInfo bug"
```

---

### Task 7: Update Dart public API on `Otpless`

**Files:**
- Modify: `lib/otpless_flutter.dart`

**Interfaces:**
- Consumes: methods from Task 6's `MethodChannelOtplessFlutter`.
- Produces: the final public Dart API a merchant calls. Every method must be present with the exact signature listed below.

- [ ] **Step 1: Rename `startBackground` → `startOnetap`**

Replace `lib/otpless_flutter.dart:49-52` with:

```dart
  Future<bool> startOnetap(
      OtplessResultCallback callback, OtplessAuthConfig config) async {
    return await _otplessChannel.startOnetap(callback, config);
  }
```

- [ ] **Step 2: Add all new methods on `Otpless`**

Above the closing brace of the class (`lib/otpless_flutter.dart:61`), insert:

```dart
  Future<void> startInBackground(
      OtplessResultCallback callback, Map<String, dynamic> jsonObject) async {
    return _otplessChannel.startInBackground(callback, jsonObject);
  }

  Future<void> setDeviceFingerprintMode(DeviceFingerprintMode mode) async {
    return _otplessChannel.setDeviceFingerprintMode(mode);
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

  Future<bool> checkSimBindingStatus() async {
    return _otplessChannel.checkSimBindingStatus();
  }

  Future<void> clearSimBinding() async {
    return _otplessChannel.clearSimBinding();
  }

  Future<void> setSimBindingEnabled(bool enabled) async {
    return _otplessChannel.setSimBindingEnabled(enabled);
  }

  Future<void> closeDialogIfOpen() async {
    return _otplessChannel.closeDialogIfOpen();
  }
```

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/otpless_flutter.dart
git commit -m "feat(dart): expose new session/MFA/fingerprint/SIM APIs on Otpless"
```

---

### Task 8: Update example app to exercise the new API + rename call sites

**Files:**
- Modify: `example/lib/main.dart` (rename `startBackground` → `startOnetap`; add MFA toggle + session buttons)

**Interfaces:**
- Consumes: `Otpless` public API from Task 7.
- Produces: nothing the plugin depends on.

- [ ] **Step 1: Locate and rename `startBackground` calls in the example**

Run: `grep -n startBackground example/lib/main.dart`
Expected: 1 or more matches.

For each match, rewrite the Dart call from:

```dart
_otplessHeadlessPlugin.startBackground(callback, config)
```

to:

```dart
_otplessHeadlessPlugin.startOnetap(callback, config)
```

- [ ] **Step 2: Add a MFA toggle button in the example UI**

Find the button row in `example/lib/main.dart` (near the other buttons that call plugin methods). Insert a `Switch` or `ElevatedButton` that calls:

```dart
await _otplessHeadlessPlugin.setMfaEnabled(true);
```

Wire it to a local `bool _mfaEnabled` state variable and update the switch accordingly.

- [ ] **Step 3: Add an "Active session" button**

Insert an `ElevatedButton` in the same UI section labelled "Active session" whose `onPressed` runs:

```dart
final session = await _otplessHeadlessPlugin.getActiveSession();
debugPrint('active session: $session');
```

- [ ] **Step 4: Run static analysis on the example**

Run: `cd example && flutter analyze lib/ && cd -`
Expected: `No issues found!`

- [ ] **Step 5: Build the example for both platforms**

Run: `cd example && flutter build apk --debug --target-platform android-arm64 2>&1 | tail -10 && cd -`
Expected: `Built build/app/outputs/flutter-apk/app-debug.apk`

Run: `cd example && flutter build ios --debug --no-codesign 2>&1 | tail -10 && cd -`
Expected: `Built /Users/.../example/build/ios/iphoneos/Runner.app`

- [ ] **Step 6: Commit**

```bash
git add example/lib/main.dart
git commit -m "docs(example): rename startBackground->startOnetap and demo MFA/session APIs"
```

---

### Task 9: Update README — platform matrix, iOS host hooks, migration note

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing.
- Produces: documentation only.

- [ ] **Step 1: Add a "Platform support matrix" section**

Insert (at an appropriate location — likely below the intro / above the "Usage" section) the table from spec §15:

```markdown
## Platform support matrix

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
| Deep-link handling / Passkey / Facebook SDK register | via manifest / no-op | client wires up in `AppDelegate` / `SceneDelegate` (see below) |
```

- [ ] **Step 2: Add an "iOS AppDelegate / SceneDelegate integration" section**

Insert after the platform matrix:

````markdown
## iOS AppDelegate / SceneDelegate integration

The plugin does not wrap URL handlers, Facebook SDK registration, or WebAuthn. If your merchant flow requires them, add the following in your host iOS app.

### Deep-link callback (required for OAuth channel types)

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

### Facebook SDK (only if using FACEBOOK_SDK channel)

Add `OtplessBM/FacebookSupport` subspec to your `ios/Podfile`. Then wire up in `AppDelegate.swift`:

```swift
override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    Otpless.shared.registerFBApp(application, didFinishLaunchingWithOptions: launchOptions)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
}
```

### Passkey / WebAuthn (only if using request-ID passkey flow)

The `OtplessBM.Otpless.shared.authorizeViaPasskey(withRequest:windowScene:)` API is not exposed through this Flutter plugin. If your flow needs it, call it from Swift with a resolved `UIWindowScene`.
````

- [ ] **Step 3: Add a "Migration from 1.x to 2.0" section**

Insert:

```markdown
## Migration from 1.x to 2.0

### Breaking changes

- **`startBackground(callback, config)` is renamed to `startOnetap(callback, config)`.** The old name misleadingly implied a background OTP flow when the method actually presented the OneTap / verified-contact sheet. Replace every call site.
- **iOS parity for `startOnetap` and `sendUserAuthEvent`.** These now execute on both platforms instead of silently returning `false` on iOS. If your app relied on iOS being a no-op, add a `Platform.isAndroid` guard on your side.
- **New `responseType` values** may arrive in the callback: `AUTH_TERMINATED`, `MFA_FACTOR_COMPLETED`, `AUTO_FLOW_ACTION` (Android only). Callers that switch exhaustively on `responseType` must add cases.
- **`OtplessAuthConfig` constructor gains an optional `deviceFingerprintMode` parameter** (defaults to `DeviceFingerprintMode.none`). Backwards compatible for positional callers; if you named the parameter, no change.

### New features

- `setDeviceFingerprintMode(DeviceFingerprintMode)` — global default fingerprint strategy. Override per request by adding a `deviceFingerprintMode` key to the `start()` map.
- `setMfaEnabled(bool)` — enable MFA. Watch for `MFA_FACTOR_COMPLETED` in your response handler.
- `initSession(appId)` / `getActiveSession()` / `logoutSession()` — JWT-based session persistence.
- `startInBackground(callback, requestMap)` — Android-only silent variant of `start()` that suppresses `OTP_AUTO_READ` intermediates.
- Android-only: `checkSimBindingStatus()`, `clearSimBinding()`, `setSimBindingEnabled(bool)`, `closeDialogIfOpen()`.

### Bug fix

- `sendUserAuthEvent(...)`: the `providerInfo` optional parameter was previously dropped due to an inverted null check on the plugin side. Fixed in 2.0.0; downstream analytics receive it now.
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: platform matrix, iOS host hooks, and 1.x->2.0 migration notes"
```

---

### Task 10: Add 2.0.0 CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md` (prepend new section)

**Interfaces:** none.

- [ ] **Step 1: Prepend the 2.0.0 section**

At the very top of `CHANGELOG.md` (above the existing `## 1.1.1 (19th Jun 2026)` line), insert:

```markdown
## 2.0.0 (27th July 2026)
### Breaking
- Renamed `startBackground(callback, config)` → `startOnetap(callback, config)`. Update all Dart call sites. See README migration section.
- Response type set grew: consumers may now receive `AUTH_TERMINATED`, `MFA_FACTOR_COMPLETED`, and (Android only) `AUTO_FLOW_ACTION` from the response callback.

### Android
- Bump `otpless-headless-sdk` to `v0.9.0`.
- New public APIs: `setDeviceFingerprintMode`, `setMfaEnabled`, `initSession`, `getActiveSession`, `logoutSession`, `startInBackground`, `checkSimBindingStatus`, `clearSimBinding`, `setSimBindingEnabled`, `closeDialogIfOpen`.
- Request-parser hardening: guards against unknown channels, empty-string setters, and now accepts `code`, `extras`, `requestId`, `deviceFingerprintMode` on the `start` / `startInBackground` request map.

### iOS
- Bump `OtplessBM/Core` to `2.3.2`.
- `startOnetap`, `sendUserAuthEvent` now execute on iOS (were previously no-ops).
- New public APIs mirroring Android: `setDeviceFingerprintMode`, `setMfaEnabled`, `initSession`, `getActiveSession`, `logoutSession`.
- Documented in README: `handleDeeplink`, `registerFBApp`, `authorizeViaPasskey` — client wires these into their own `AppDelegate` / `SceneDelegate`.

### Fixes
- `sendUserAuthEvent`: `providerInfo` optional parameter is now actually forwarded to the native SDK (previously silently dropped due to inverted null check).
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add 2.0.0 changelog"
```

---

### Task 11: Final verification and publish dry-run

**Files:** none.

**Interfaces:** all prior tasks.

- [ ] **Step 1: Run `flutter analyze` on the entire plugin**

Run: `flutter analyze`
Expected: `No issues found!` — zero warnings, zero errors.

If issues appear, fix them inline (they will typically be dead imports or missing type annotations) and re-run.

- [ ] **Step 2: Run existing test suite**

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 3: Run `dart format` and verify no changes needed**

Run: `dart format . --set-exit-if-changed`
Expected: exits 0 with no reformatting needed. If the command reformats files, review the changes and either accept + commit or restore what was intentional.

- [ ] **Step 4: Publish dry-run**

Run: `flutter pub publish --dry-run 2>&1 | tail -40`
Expected: `Package has 0 warnings.` (or a small number of allowed warnings like the LICENSE reference). No errors.

If dry-run reports issues around missing `LICENSE` or `readme` — fix by ensuring the repo root has both files intact.

- [ ] **Step 5: Full example app run — Android**

Run on a connected Android device or emulator:

```
cd example && flutter run -d <device-id>
```

Manual smoke test checklist inside the running app:
- Initialize the SDK.
- Call `start` with a phone number; confirm OTP flow.
- Toggle the MFA switch (added in Task 8); confirm no crash.
- Tap the "Active session" button; confirm a Map with `isActive` prints.
- Call `startOnetap`; confirm OneTap sheet appears.

- [ ] **Step 6: Full example app run — iOS**

Run on a connected iOS device or simulator (physical device required for iOS 15+ OneTap flow):

```
cd example && flutter run -d <ios-device-id>
```

Manual smoke test checklist inside the running app:
- Initialize the SDK.
- Call `start` with a phone number; confirm OTP flow.
- Call `startOnetap` — confirm sheet appears (previously was a no-op).
- Tap "Active session" — confirm Map prints.
- Call `sendUserAuthEvent` with any provider info — no crash.

- [ ] **Step 7: Final commit if any fixup was needed during smoke test**

If the smoke test required a code fix:

```bash
git add -u
git commit -m "fix: <brief description of the smoke test finding>"
```

Otherwise, no commit needed for Task 11.

---

## Self-Review Checklist (post-implementation)

After all 11 tasks complete, verify:

- [ ] The final `pubspec.yaml` shows `version: 2.0.0`.
- [ ] `grep -r "startBackground" lib/ android/ ios/ example/ README.md CHANGELOG.md` returns **only** references inside migration notes or CHANGELOG (i.e., no live code still calls `startBackground`).
- [ ] `grep -rn "userAuthEvent" lib/ android/ ios/` returns exactly three matches: the Dart channel invocation, the Kotlin `when` case, and the Swift `switch` case — all three should agree on the string `"userAuthEvent"`.
- [ ] `grep -n "if (providerInfo == null)" lib/` returns zero matches (bug fix in place).
- [ ] `flutter analyze` exits clean.
- [ ] `flutter test` passes.
- [ ] `flutter pub publish --dry-run` reports no errors.
- [ ] `example/` builds on both Android and iOS.
