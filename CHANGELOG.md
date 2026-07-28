## Unreleased

### Repo & tooling

- Brought the repo to agentic development readiness: a `CLAUDE.md` constitution,
  a `make gate` verification gate (`dart format` + `flutter analyze --fatal-infos`
  + `flutter test` + a public-Dart-surface golden + mechanical doc/bridge checks),
  `.claude/skills/*` protocols, repo guard hooks, and six CI workflows
  (build-test, docs-verify, size-check, docs-sync, docs-audit, `@claude`).
- Added `api/dart-surface.txt`, a committed golden of the public Dart API
  (`scripts/dart_surface.py`). Parameter names and enum values are included,
  because Dart callers use named arguments and enum `.name` is the value sent
  over the method channel — so renaming either is a breaking change that would
  otherwise compile silently.
- Added `scripts/docs-verify.sh`, which mechanically checks **method-channel
  parity**: every `invokeMethod` name in `lib/` must have a handler in both the
  Kotlin and Swift bridges. The channel is a stringly typed contract across
  three languages with no compiler spanning it, so a half-ported method
  previously reached merchants before anything failed.
- **Fixed: the example app could not be built without a release keystore.**
  `example/android/app/build.gradle` configured `signingConfigs.release`
  unconditionally, and because `signingConfigs` is evaluated at configuration
  time, `file(null)` failed *every* Gradle task — including `assembleDebug` —
  with "path may not be null or empty string". Release signing is now optional
  and falls back to the debug keys. This was required to make the Kotlin bridge
  verifiable at all.
- **Fixed: the podspec hardcoded `s.version = '0.0.1'`** while the package
  shipped as 2.0.0, which also pointed `s.source`'s `:tag` at a git tag that
  never existed. The version is now derived from `pubspec.yaml` at parse time,
  and the gate fails if a literal version reappears.
- Excluded repo tooling (`.claude/`, `.github/`, `scripts/`, `api/`, `Makefile`,
  `CLAUDE.md`, `test/`) from the published pub package via `.pubignore`.
- Removed `CLAUDE.md` from `.gitignore` — the constitution must be tracked.
- Added `docs/SDK-GUIDE.md`: the canonical description of the plugin — all three
  layers, every one of the 19 channel methods end-to-end, the response contract
  and both marshalling directions, request-key tables per platform, the platform
  asymmetry matrix, build/toolchain facts, and 15 verified quirks. Its § numbers
  are stable identifiers referenced from CLAUDE.md and the skills.
- `make gate` now depends on a `deps` target (`flutter pub get`). Without a
  resolved package config, `dart format` selects a different default language
  version and reports every file as needing reformatting, so the gate failed on
  a fresh clone for a reason unrelated to the diff.

### Known issues (documented, not yet fixed)

- `initialize`'s `timeout` parameter is accepted by the Dart API and sent over
  the channel, but **neither native bridge reads it** — it has no effect.
- The Kotlin `initialize` handler reads a `loginUri` argument that the Dart layer
  never sends, so the deep-link login URI cannot be set from Flutter.
- `cleanup` is implemented in both native bridges but reachable from no Dart API,
  so in-flight jobs/tasks cannot be cancelled by a merchant.
- `setDevLogging(false)` does not disable logging on iOS: the logger delegate is
  installed when enabling and never removed.
- The iOS dispatch's `default:` branch returns without calling `result`, so an
  unknown channel method leaves the Dart `Future` pending forever (Android
  correctly returns `notImplemented()`).
- Several iOS handlers force-unwrap channel arguments (`call.arguments as!`,
  `args["arg"] as!`), which would crash the host app on a malformed call.

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