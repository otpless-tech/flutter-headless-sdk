<!--
Delete nothing. Answer every line — "n/a" is a valid answer, silence is not.
The constitution is in CLAUDE.md; the reviewer works through it in order via
the pr-review skill.
-->

## What & why

<!-- One paragraph. What behavior changes for a merchant, and why. -->

## Parity statement (REQUIRED — hub change-flow rules 1–3)

<!-- Exactly one. This repo shares the android-full + iOS lane with react-native-headless-sdk. -->

- [ ] `Parity: ported in <repo>#NN`
- [ ] `Parity: N/A — <reason>`
- [ ] `Parity: port ticket <link>`

## Bridge layers touched

<!-- A channel method must exist in Dart, Kotlin AND Swift, or be explicitly
     rejected on one platform with a documented reason. -->

- [ ] Dart public API (`lib/otpless_flutter.dart`)
- [ ] Dart channel (`lib/otpless_flutter_method_channel.dart`)
- [ ] Android bridge (Kotlin)
- [ ] iOS bridge (Swift)
- [ ] None — Dart-only / docs-only change

## Verification

<!-- Paste actual output or say what you could not run. Claims without evidence
     are rejected. `flutter test` alone is NOT verification for a bridge change. -->

- [ ] `make gate` green — paste the tail:
- [ ] `make example-android` (required if `android/` changed):
- [ ] `make example-ios` (required if `ios/` changed):
- [ ] Flow exercised manually in `example/` — which flows:
- [ ] Could not verify: <what, and why>

## Constitution checklist

**1. Public API is a contract**
- [ ] No public Dart surface change, OR `make surface-dump` refreshed and reviewed in this PR
- [ ] No parameter renames, enum reorderings, or channel-method renames (all breaking)
- [ ] Breaking changes have a `### Breaking` CHANGELOG entry and a major version bump

**2. Never harm the host app**
- [ ] No new force-unwraps on channel arguments (Swift `as!`) or on the Dart callback
- [ ] Every code path calls `result(...)` exactly once — no path leaves the Dart `Future` pending
- [ ] No main-thread blocking; in-flight work cancelled on detach
- [ ] No new permissions / `<queries>` / Info.plist keys (or: product sign-off linked)

**3. Privacy & auditability**
- [ ] No PII (phone, OTP, token, identity) reachable from logs
- [ ] Response payloads marshalled **verbatim** — no keys renamed, filtered or reshaped

**4. Naming**
- [ ] No OTPLESS codenames or SNA partner names introduced
- [ ] `dart format` clean; channel keys `lowerCamelCase` and read by both natives

**5. Dependencies & size**
- [ ] No new runtime dependency (or: justified below)
- [ ] Native pins remain exact versions, not ranges

**6. Docs**
- [ ] `CHANGELOG.md` updated (merchant-visible phrasing — this is what the public-docs automation reads)
- [ ] `docs/SDK-GUIDE.md` updated, or unaffected

## Notes for the reviewer

<!-- Known gaps, follow-ups, anything deliberately out of scope. -->
