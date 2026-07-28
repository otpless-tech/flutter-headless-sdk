# CLAUDE.md — flutter-headless-sdk

Instructions for Claude Code (and any AI agent) working in this repository. Human developers: the same rules apply to you.

## What this repo is

The **OTPLESS headless Flutter plugin** (pub package `otpless_headless_flutter`). It is a **wrapper**, not an SDK: it owns no authentication logic. It marshals calls across a `MethodChannel` to the two native SDKs it pins, and marshals their responses back:

| Layer | Files | Pins |
|---|---|---|
| Dart public API | `lib/otpless_flutter.dart`, `lib/models.dart` | — |
| Channel plumbing | `lib/otpless_flutter_method_channel.dart`, `lib/otpless_flutter_platform_interface.dart` | `MethodChannel('otpless_headless_flutter')` |
| Android bridge | `android/src/main/kotlin/com/otpless/headlessflutter/*.kt` | `io.github.otpless-tech:otpless-headless-sdk` |
| iOS bridge | `ios/Classes/*.swift` | `OtplessBM/Core` |

`example/` is a **testbed — never document it, never treat its changes as plugin changes.** The one exception: its build is the only proof the native bridges compile (`make example-android` / `make example-ios`).

Start every non-trivial task by reading **`docs/SDK-GUIDE.md`** — the canonical description of this plugin (layers, every channel method end-to-end, the response contract, platform asymmetries, quirks). Do not re-derive the architecture; trust the guide, verify against code where it matters, and fix the guide if they disagree.

> **Sibling context.** The parent workspace `CLAUDE.md` (loaded automatically) carries the cross-repo topology and the four change-flow rules. The two facts that bind this repo: it consumes **android-full + iOS**, the same lane as `otpless-rn-full`; and the response contract is backend-driven, so this wrapper **marshals payloads verbatim and must never reshape them**.

### Making code changes: use the guide first, read code narrowly

1. **Locate via the guide** — find the channel method or flow in `docs/SDK-GUIDE.md`. It names the exact Dart method, the channel string, and both native handlers.
2. **Read the three layers for that one method** — Dart, Kotlin, Swift. They are small files; read them in full. Do not sweep the repo.
3. **Verify before editing** — code is the source of truth. If it disagrees with the guide, the guide is stale: do the task, then fix the guide.
4. **Make the change on all layers that need it.** A channel method touched on one platform and not the other is the single most common defect class in this repo — see article 1.

## Build & test

```bash
flutter test                # Dart unit tests
flutter analyze --fatal-infos
```

The full verification gate. The canonical definition is the `GATE_CMD` variable + `gate` target in the root `Makefile` — change the gate **there first**; `docs-verify.sh` check 6 fails the build if the copies here, in CI, or in the verify skill drift from it:

```bash
make gate
# which runs:
dart format --output=none --set-exit-if-changed lib test && flutter analyze --fatal-infos lib test && flutter test
python3 scripts/dart_surface.py --check
bash scripts/docs-verify.sh
```

- `dart_surface.py --check` diffs the public Dart surface against `api/dart-surface.txt`. This is the mechanical public-API contract (the Flutter analogue of android-lite's binary-compatibility-validator dump). Parameter **names** are included because Dart callers use named arguments, and enum **values** are included because `.name` is what crosses the channel.
- `docs-verify.sh` checks version single-sourcing, native-pin/changelog agreement, **method-channel parity across Dart/Kotlin/Swift**, channel-name agreement, golden freshness, and gate drift.
- **`make gate` does not compile the native bridges.** `flutter test` never loads Kotlin or Swift. Any change under `android/` or `ios/` additionally requires `make example-android` / `make example-ios` — see the **verify** skill's ladder.
- **Version lives only in `pubspec.yaml`.** The podspec derives it at parse time; `docs-verify.sh` fails if a literal version reappears there.
- Native pins: `android/build.gradle` (`otpless-headless-sdk`) and `ios/otpless_headless_flutter.podspec` (`OtplessBM/Core`). Changing either is a **merchant-visible** change — see the **bump-native-sdk** skill.

---

## Repo protocols — invoke the skill, don't improvise

| Skill | When it applies |
|---|---|
| **verify** | Before claiming any change works. Climbs Dart tests → gate → native example builds → manual device smoke. `flutter test` alone is never verification for a bridge change. |
| **bridge-method** | Adding, renaming, or removing a channel method — the cross-cutting recipe across five files (Dart API, Dart channel, Kotlin, Swift, golden) plus docs, whose steps `docs-verify.sh` checks mechanically. |
| **bump-native-sdk** | Bumping `otpless-headless-sdk` or `OtplessBM/Core`. Diffs the upstream's committed API goldens between versions to enumerate bridge work, then runs the gate + example builds. |
| **docs-sync** | Any time `lib/`, `android/` or `ios/` changed and `docs/SDK-GUIDE.md` / `CHANGELOG.md` must catch up. Owns `docs/.doc-sync-state` and the `[docs-sync]` commit marker. |
| **add-tests** | Writing Dart tests — the `TestDefaultBinaryMessengerBinding` recipe, what is and isn't testable from Dart, contract-fixture rules. |
| **pr-review** | Reviewing any PR or diff against the six constitution articles below, in order, before merge. |
| **release** | Cutting a release: version bump in `pubspec.yaml` → changelog promotion → `flutter pub publish`. |
| **size-review** | Every PR touching `lib/`/`android/`/`ios/`: package size and the transitive weight the plugin imposes on merchant apps. |

`docs/.doc-sync-state` holds the commit SHA the docs were last synced to; doc-sync commits use the `[docs-sync]` marker and contain only doc files.

---

## Plugin development constitution (MANDATORY for every code change)

This plugin runs inside merchants' Flutter apps. We are a guest in their process: their crash rate, their startup time, their app size, and their security review all include us. These rules outrank convenience; exceptions require an explicit decision recorded in the PR and the changelog.

### 1. The public API is a contract — and it spans three languages

- **The channel is a stringly typed contract with no compiler.** Nothing in Dart, Kotlin or Swift fails to build when a method name is misspelled, half-ported, or removed on one platform only. A channel method MUST be implemented on **both** natives or explicitly rejected on one with a documented reason. `docs-verify.sh` check 3 enforces this; never silence it.
- **Never declare a native handler with no implementation.** rn-full ships `RCT_EXTERN_METHOD` declarations whose Swift bodies don't exist, so any call crashes with "unrecognized selector" (hub `docs/PARITY.md` C8). Do not reproduce that shape here.
- **Semver discipline.** Breaking anything a merchant observes — Dart signatures, parameter *names*, enum values or their order, channel payload keys, response shape, default behavior — needs a major-version decision and a `### Breaking` changelog entry. When in doubt, it's breaking.
- **Parameter names and enum values are API.** Dart callers use named arguments; enum `.name` is the wire value sent to native. Renaming `enabled` → `isEnabled`, or reordering an enum, is a break even though both compile.
- **Deprecate, then remove — never remove cold.** `@Deprecated('use X instead')`, keep working for at least 2 minor releases, then remove.
- **Additive evolution only:** new optional named parameters with defaults, new methods, new response fields. Never repurpose an existing name.
- **`api/dart-surface.txt` is the mechanical contract.** Any public-surface change requires a reviewed `make surface-dump` in the **same PR**.
- **Never leak plugin internals or third-party types** through the public Dart API. Responses cross as plain `dynamic`/`Map<String, dynamic>` decoded from JSON — merchants must never be forced onto our types.

### 2. Never harm the host app

- **Never crash the merchant app.** This is the article this repo has historically broken:
  - Swift force-unwraps on channel arguments (`call.arguments as! [String: Any]`, `args["arg"] as! String`) turn a malformed call into a **host-app crash**. Use `guard let` and fail the `result` instead.
  - Dart force-unwraps the response callback (`_callback!`) — if a native response arrives before the merchant registers a callback, this throws inside the platform message handler.
  - Never let an exception escape a channel handler or a callback into merchant code.
- **Always answer the channel.** Every `result(...)`/`result.success/error` path must be reached exactly once. iOS's dispatch `default: return` never calls `result`, so an unknown method leaves the Dart `Future` **pending forever** — Android correctly uses `notImplemented()`. A hung future is as bad as a crash and much harder to diagnose.
- **Never block the main thread.** Native work goes to `Dispatchers.IO` / a `Task`; merchant callbacks are delivered on the platform's main thread. An SDK-caused ANR is a sev-1.
- **Undo every side effect.** Cancel in-flight jobs/tasks and release listeners on detach. Assume the merchant app lives for days and the Flutter engine attaches/detaches repeatedly.
- **No surprises in the manifest or Info.plist merge.** New permissions or `<queries>` entries require product sign-off — enterprise security teams diff these on every update.
- **Fail safe, not loud.** A capability absent on a platform returns a defined neutral value (`false`, `null`, no-op) and is documented as such — it never throws.

### 3. Privacy & auditability

- **The wrapper adds no data collection.** All telemetry originates in the native SDKs. If this plugin ever collects or forwards anything itself, it needs product sign-off and a same-PR `docs/SDK-GUIDE.md` entry.
- **No PII in logs, ever.** Phone numbers, OTPs, tokens and identities must not reach `print()`/logcat/NSLog. `setDevLogging` gates verbose native logging; the plugin's own code should not log payloads at all. Note the current asymmetry: iOS only *installs* a logger delegate when enabling and never removes it, so `setDevLogging(false)` does not disable iOS logging — treat that as a bug, not a pattern.
- **Marshal verbatim.** Response payloads are backend-driven and shared with android-full and iOS. Do not filter, rename, reshape, or "clean up" keys in transit — a wrapper that edits the contract silently breaks platform parity (hub rule 4).

### 4. Naming conventions

- **Public Dart API speaks merchant language.** `Otpless*` prefixes, descriptive and boring. Internal OTPLESS codenames (`LongClaw`, `QuantumLeap`) and SNA partner names (Sekura, Jio, IPification, Airtel — server-selected) never appear, even in comments.
- **Dart style:** `UpperCamelCase` types, `lowerCamelCase` members and enum values, `dart format` clean (enforced by the gate).
- **Channel method names** are `lowerCamelCase` and match the Dart method they serve. They are permanent once shipped — a rename is a breaking change on three layers at once.
- **Channel argument keys** are `lowerCamelCase` and must match what both natives read. A key written by Dart and read by neither native is dead weight; a key read by a native and never written is a silent no-op (`loginUri` is the current example).
- **JSON payload keys** match the backend contract exactly. Never invent a synonym for a concept that already has a key.

### 5. Dependencies & size

- **Default answer to a new dependency is no.** The plugin's runtime deps are `flutter` and `plugin_platform_interface` only; that is a feature. Every addition lands in every merchant's app and every security scan.
- **Never widen the native pins to a range.** Pin exact versions (`0.9.0`, not `^0.9.0`) so a merchant's build is reproducible and a native release cannot change behavior without a reviewed PR here.
- **Stay conservative on Flutter/Dart minimums.** Raising `environment: sdk` or the Flutter constraint drops merchants; it is a breaking change requiring a major bump.

### 6. Verification before merge

- **Run the full gate, not a subset:** `make gate`.
- **`flutter test` proves only the Dart layer.** It cannot see Kotlin or Swift. Any diff touching `android/` or `ios/` requires the matching example build; state in the PR which you ran.
- **Both platforms, every time.** A bridge change verified on one platform is not verified. If you cannot build the other, say so explicitly in the PR rather than implying coverage.
- **Exercise the changed flow end-to-end** in `example/` for behavioral changes (init → start → response), and say which flows you exercised.
- **Parity statement required.** Every merchant-visible PR carries `Parity: ported in <repo>#NN` / `Parity: N/A — <reason>` / `Parity: port ticket <link>` per hub rules 1–3. This repo shares the android-full + iOS lane with `otpless-rn-full`; changes here usually apply there too.

## General working rules

- **Git workflow:** `main` is protected — never push it directly (a `.claude/settings.json` rule also denies it locally). Work on a feature branch, open a PR, fill the template's constitution checklist. CI on every PR: `build-test` (the gate), `docs-verify`, `size-check`, `actionlint`.
- **Worktree-driven development:** the primary checkout belongs to the human — never switch its branches or reset its state to do agent work. Every independent task, and every agent working in parallel with another, gets its own `git worktree` (`git worktree add /tmp/<repo>-<task> <branch>`), commits and pushes from there, and removes it when done.
- **Never document or refactor `example/`** unless explicitly asked; it is a testbed.
- **`docs/superpowers/`** holds design specs and plans from prior agent sessions (e.g. the 2.0.0 version-alignment work). Read the relevant one before redoing analysis it already contains; it is history, not a source of truth about current code.
- Response payloads cross the channel as **JSON strings**, not structured maps (`json.encode` in Dart, `JSONObject`/`JSONSerialization` natively). Match that pattern; do not send a raw `Map` for a payload the other side decodes as a string.
- The `otpless_callback_event` reverse invocation is the **only** path from native to Dart. Keep it that way — a second callback channel would fragment ordering guarantees.
