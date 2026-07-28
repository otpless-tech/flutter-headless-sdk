---
name: pr-review
description: Review any PR or diff touching the OTPLESS Flutter plugin against the six constitution articles in CLAUDE.md. Use when asked to review a pull request, review a diff, or check a change before merge.
---

# Reviewing a PR in flutter-headless-sdk

Work the six constitution articles **in order**. Article 1 and 2 findings block merge; the rest are negotiable with a recorded reason.

Start by reading the diff in full. `git diff main...HEAD`. Then walk the articles.

## Before the articles: the three-layer question

For **every** channel method the diff touches, confirm all four exist:

1. Dart public API (`lib/otpless_flutter.dart`)
2. Dart channel call (`lib/otpless_flutter_method_channel.dart`)
3. Android handler (`"name" ->`)
4. iOS handler (`case "name":`)

...or an explicit, documented rejection on one platform. `bash scripts/docs-verify.sh` check 3 answers this mechanically — run it, don't eyeball it. A half-ported method compiles on all three layers and fails only in a merchant's app.

## Article 1 — public API is a contract

- Is `api/dart-surface.txt` refreshed **in this PR** if public surface moved? A missing golden update is a blocking finding.
- Does the golden diff contain **only** intended changes? An unexpected line means the author changed more surface than they realized.
- Any of these present and *not* marked breaking with a major bump?
  - renamed parameter (Dart callers use named args)
  - reordered or renamed enum value (`.name` is wire format)
  - renamed channel method
  - changed default value or return type
  - removed method without a deprecation cycle
- Is a new `public` symbol actually needed, or should it be private?

## Article 2 — never harm the host app

This repo's weak spot. Check every added or modified native handler:

- **Swift force-unwraps on channel input** — `call.arguments as! [String: Any]`, `args["x"] as! String`. Any new one is a blocking finding: it converts a malformed call into a host-app crash. Require `guard let` + a `result` on the failure path.
- **`result` called exactly once on every path.** Look for early `return`s that skip it — those hang the Dart `Future` forever. Note that iOS's dispatch `default: return` already does this; a new case must not add to the problem.
- **Dart force-unwraps** — `_callback!` and friends.
- Main-thread work: SDK calls belong on `Dispatchers.IO` (Android) or inside a `Task` (iOS), answering on main.
- Cancellation: is in-flight work cancelled on detach / on a new call, and are `WeakReference`/`weak self` used so a detached activity can't leak?
- New permissions, `<queries>`, or Info.plist keys → needs product sign-off linked in the PR.

## Article 3 — privacy & auditability

- Any `print`/`Log`/`NSLog` that could carry a phone number, OTP, token, or identity? Blocking.
- Are response payloads passed **verbatim**? A wrapper that renames, filters, or reshapes keys silently breaks platform parity (hub rule 4). Look for map rebuilding in either bridge.
- Does the plugin now collect anything itself? It shouldn't — telemetry belongs to the natives.

## Article 4 — naming

- OTPLESS codenames (`LongClaw`, `QuantumLeap`) or SNA partner names (Sekura, Jio, IPification, Airtel) anywhere, including comments? Remove.
- `dart format` clean (the gate enforces it).
- New channel argument keys: `lowerCamelCase`, and **read by both natives**. A key sent and never read, or read and never sent, is a finding — the existing `timeout` (sent, read by nobody) and `loginUri` (read, never sent) are the precedents to avoid repeating.

## Article 5 — dependencies & size

- New runtime dependency in `pubspec.yaml`? Default answer is no; require justification.
- Native pins still **exact**, never a range.
- `environment:` / Flutter constraint raised? That drops merchants — breaking.

## Article 6 — verification

Judge the evidence, not the claim.

- Is `make gate` output pasted, or just asserted? "Tests pass" is not evidence.
- **Diff touches `android/`?** `make example-android` is required. **`ios/`?** `make example-ios` is required. `flutter test` cannot compile either bridge — if the author implies otherwise, correct it.
- Behavioral change → which flows were exercised in `example/`, on which platform?
- Did a new `WARN` appear in `docs-verify.sh`? Ask why.
- **Parity statement present?** Required on every merchant-visible PR. This repo shares the android-full + iOS lane with `react-native-headless-sdk`, so most changes here apply there too. A missing statement is a blocking finding under hub rules 1–3.

## Writing the review

- Lead with blocking findings; separate them clearly from suggestions.
- Cite `file:line` for every finding.
- Quote the article you're invoking, so the author can argue with the rule rather than guess at taste.
- If you could not verify something (no Xcode, no device), say so explicitly instead of implying the PR is fully checked.
- Approving a PR whose verification section is empty is itself a review failure.
