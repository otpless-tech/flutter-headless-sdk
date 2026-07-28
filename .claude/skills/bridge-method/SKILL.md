---
name: bridge-method
description: Recipe for adding, renaming, or removing a method channel method in the OTPLESS Flutter plugin. Use when exposing a new native capability to Dart, changing a channel method's arguments, or removing one — the change fans out across five files plus docs, and a half-completed port compiles cleanly on every layer.
---

# Adding or changing a channel method

**Why this needs a recipe:** the method channel is a stringly typed contract across three languages with no compiler spanning them. Dart compiles fine calling a method no native implements. Kotlin compiles fine handling a method no one calls. Swift compiles fine omitting a method entirely. The failure surfaces as a hung `Future` or a crash in a merchant's app. `scripts/docs-verify.sh` check 3 is the mechanical backstop — treat it as the definition of done, not an obstacle.

## The five files, in order

For a channel method `fooBar`:

| # | File | What goes in |
|---|---|---|
| 1 | `lib/otpless_flutter.dart` | Public Dart API — the merchant-facing signature |
| 2 | `lib/otpless_flutter_method_channel.dart` | `methodChannel.invokeMethod("fooBar", {...})` + platform guards |
| 3 | `android/src/main/kotlin/com/otpless/headlessflutter/OtplessFlutterHeadless.kt` | `"fooBar" -> { ... }` in `onMethodCall` |
| 4 | `ios/Classes/SwiftOtplessFlutterHeadless.swift` | `case "fooBar":` in `handleOnMainThread` |
| 5 | `api/dart-surface.txt` | via `make surface-dump` — never hand-edited (a hook blocks it) |

Then: `CHANGELOG.md` (merchant-visible phrasing) and `docs/SDK-GUIDE.md`.

## Step by step

### 1. Decide the platform story first

Before writing anything, answer: **does this exist on both natives?** Three legitimate answers:

- **Both** — implement both. Default case.
- **Android only** (e.g. TrueCaller, SIM binding, WhatsApp detection) — guard in **Dart**, so the call never crosses the channel on iOS:
  ```dart
  Future<bool> checkSimBindingStatus() async {
    if (!Platform.isAndroid) return false;   // guard here...
    ...
  }
  ```
  and *still* add a defensive `case` in Swift returning the same neutral value. The Dart guard is the contract; the Swift case is belt-and-braces for a future refactor that drops the guard. This is the existing pattern — follow it.
- **iOS only** — same shape, mirrored.

Record the answer in the SDK-GUIDE. An undocumented asymmetry is how `startOnetap` and `sendUserAuthEvent` silently no-opped on iOS before 2.0.0.

### 2. Write the Dart public API (file 1)

- `lowerCamelCase`, `Future`-returning, named optional parameters for anything optional.
- Parameter **names are API** — merchants use named arguments. Choose them once.
- Return a defined neutral value where a platform can't help (`false`, `null`), never throw.

### 3. Write the channel call (file 2)

- The channel method name **must equal** the Dart method name unless there's a documented reason. `docs-verify.sh` doesn't enforce equality, reviewers do.
- Argument keys: `lowerCamelCase`, and **every key must be read by both natives**. A key Dart sends that neither native reads is dead weight; a key a native reads that Dart never sends is a silent no-op — `loginUri` in the Kotlin `initialize` handler is the live example of the latter, and `timeout` in Dart's `initialize` is the live example of the former (sent, read by nobody).
- Payloads that are maps go as **JSON strings** (`json.encode(...)` under an `'arg'` key), matching `start`/`startOnetap`/`startInBackground`. Simple scalars go as plain keys. Don't invent a third convention.

### 4. Write the Android handler (file 3)

```kotlin
"fooBar" -> {
    val enabled = call.argument<Boolean>("enabled") ?: false   // never force-unwrap
    OtplessSDK.something(enabled)
    result.success(null)                                       // exactly once
}
```

- **`result` must be called exactly once on every path**, including early returns. `onMethodCall`'s `else -> result.notImplemented()` handles unknown methods; don't add a path that returns without answering.
- Anything touching the SDK goes on `Dispatchers.IO` via `lifecycleScope.launch` — the handler runs on the platform main thread.
- Guard `activity.get()` — it's a `WeakReference` and can be null before attach. Return the neutral value, don't throw.

### 5. Write the iOS handler (file 4)

```swift
case "fooBar":
    guard let args = call.arguments as? [String: Any] else {   // NOT `as!`
        result(false)
        return
    }
    let enabled = (args["enabled"] as? Bool) ?? false
    Otpless.shared.setSomething(enabled)
    result(nil)
```

- **Never `as!` on channel arguments.** `call.arguments as! [String: Any]` and `args["arg"] as! String` turn a malformed call into a host-app crash. The existing `start`/`initialize`/`startOnetap` cases still do this — do not copy them; they are a known defect (constitution article 2), not the pattern.
- **Always call `result`.** The dispatch's `default: return` never does, so an unknown method leaves the Dart `Future` pending forever. Your case must not add to that.
- `async` work goes in a `Task { ... }` and answers on the main queue: `DispatchQueue.main.async { result(...) }`.

### 6. Refresh the golden and docs

```bash
make surface-dump          # then REVIEW the diff line by line
bash scripts/docs-verify.sh
```

- The golden diff should contain exactly your intended change and nothing else. An unexpected line means you changed more surface than you meant to.
- `CHANGELOG.md`: one bullet under the top-most section, phrased as merchant-visible behavior. This is the primary signal for the public-docs automation.
- `docs/SDK-GUIDE.md`: add the method to the channel-method table with its platform story.

### 7. Verify

`make gate`, then **rung 2 of the verify skill** — `make example-android` and `make example-ios`. A new native handler that doesn't compile is invisible to `flutter test`.

## Renaming a channel method

A rename is **breaking on three layers at once** and needs a major version bump. Prefer adding the new name and deprecating the old:

1. Add the new Dart method; mark the old `@Deprecated('use fooBar instead')`.
2. Handle **both** channel names natively for at least 2 minor releases.
3. Remove the old only after the deprecation window, in a major release.

`startBackground` → `startOnetap` in 2.0.0 was a cold rename with a `### Breaking` entry — acceptable because it was a major bump, but the deprecation path is preferred.

## Removing a channel method

Remove the Dart API first and ship it; remove the native handlers a release later. Removing native first turns any straggler caller into a hung `Future` (iOS) — a `WARN` from `docs-verify.sh` about an unreachable native handler is the *safe* intermediate state, which is why it's a warning and not a failure.

## Checklist

- [ ] Platform story decided and documented (both / Android-only / iOS-only)
- [ ] Dart public API added, parameter names final
- [ ] Channel call added; every argument key read by both natives
- [ ] Android handler: no force-unwrap, `result` exactly once, IO dispatch
- [ ] iOS handler: no `as!`, `result` on every path
- [ ] `make surface-dump` run and the diff reviewed
- [ ] `CHANGELOG.md` bullet in merchant language
- [ ] `docs/SDK-GUIDE.md` channel-method table updated
- [ ] `make gate` green with no new WARN
- [ ] `make example-android` and `make example-ios` both run (or the gap stated in the PR)
- [ ] Parity statement in the PR (rn-full shares this lane)
