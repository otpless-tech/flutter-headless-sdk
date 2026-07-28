---
name: verify
description: Verification ladder for changes to the OTPLESS Flutter plugin. Use before claiming any change works, after modifying lib/ or android/ or ios/, or when asked to verify or prove a change — `flutter test` alone is never verification for a bridge change, because it cannot load Kotlin or Swift.
---

# Verifying a change in flutter-headless-sdk

**The rule that matters here:** this plugin's tests run entirely in Dart. `flutter test` spins up a fake method channel and never compiles, loads, or executes one line of Kotlin or Swift. A bridge change with green `flutter test` is **unverified**. Climb the ladder until you reach the rung that actually covers your diff, and state in the PR which rung you reached.

## Rung 0 — the gate (always, no exceptions)

```bash
make gate
# which runs:
dart format --output=none --set-exit-if-changed lib test && flutter analyze --fatal-infos lib test && flutter test
python3 scripts/dart_surface.py --check
bash scripts/docs-verify.sh
```

The gate's canonical definition is `GATE_CMD` in the root `Makefile`. If you change it there, update `CLAUDE.md`, `.github/workflows/build-test.yml` and this file in the same commit — `docs-verify.sh` check 6 fails on drift.

What each part actually proves:

| Step | Proves | Does NOT prove |
|---|---|---|
| `dart format --set-exit-if-changed` | formatting is canonical | anything about behavior |
| `flutter analyze --fatal-infos` | no analyzer diagnostics in Dart | Kotlin/Swift compile |
| `flutter test` | the Dart layer marshals as expected against a **fake** channel | that any native handler exists |
| `dart_surface.py --check` | public Dart API matches the committed golden | that the API works |
| `docs-verify.sh` | version single-sourcing, native pins recorded, **channel-method parity across all three languages**, channel names agree, golden fresh, gate not drifted | that the native implementations are correct |

`docs-verify.sh` check 3 is the closest thing to a cross-language type check this repo has. It proves every Dart `invokeMethod` name has a handler in *both* natives. It cannot prove the handler does the right thing.

## Rung 1 — Dart-only diffs stop here

If your diff touches **only** `lib/`, and adds no new `invokeMethod` call, rung 0 is sufficient. Say so in the PR.

## Rung 2 — native bridge compiles (REQUIRED if `android/` or `ios/` changed)

```bash
make example-android    # required when android/ changed
make example-ios        # required when ios/ changed
```

These are the only checks that compile Kotlin against the pinned `otpless-headless-sdk` and Swift against the pinned `OtplessBM/Core`. A renamed native SDK symbol, a wrong type, a missing import — none of it surfaces before this rung.

- `make example-android` needs a JDK and `ANDROID_HOME`.
- `make example-ios` needs Xcode; it uses `--no-codesign`, so no signing identity is required.
- If you cannot run one of them, **say which one and why in the PR** — do not let a reviewer assume coverage you don't have. Both run in CI on every PR, so a missing local run is recoverable; a silently implied one is not.

## Rung 3 — behavior on a real device/simulator (human, for flows)

Required for any change to auth flow behavior, response handling, or lifecycle:

```bash
cd example && flutter run
```

Exercise: `initialize` → `start` → response callback. State which flows you exercised.

Only a real device proves:
- responses actually arrive over `otpless_callback_event` (the fake channel in tests can't)
- nothing crashes on a malformed channel payload (Swift force-unwraps are the risk — constitution article 2)
- no `Future` hangs forever (iOS's dispatch `default:` never calls `result`)
- SNA / carrier-attribution and auto-read flows, which need real network and SIM

## Rung 4 — both platforms, every time

A bridge change verified on Android only is **half verified**. The two natives diverge by construction here (several methods are Android-only no-ops on iOS), so "it works on Android" carries no information about iOS. If you only have one platform, state that plainly.

## What to paste in the PR

Real output, not a claim. The PR template has slots for the gate tail and each example build. If a rung was skipped, write which and why. "Verified" with no evidence is rejected at review (see the **pr-review** skill).

## Common traps

- **`flutter test` passing means very little here.** It is a Dart-level passthrough check. Do not report it as "tests pass, change verified".
- **A green gate with a new `WARN` is a finding.** `docs-verify.sh` warns about native handlers with no Dart caller (currently `cleanup` on both platforms — a real gap, since Dart exposes no way to reach it). Don't add to that list.
- **Regenerating the golden is not verification.** `make surface-dump` makes the check pass by definition. Review the diff and justify the API change; don't launder it.
- **`flutter clean` between example builds** if you changed native pins — stale Gradle/Pod caches will happily link the old version.
