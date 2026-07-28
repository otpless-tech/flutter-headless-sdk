---
name: bump-native-sdk
description: Bump the pinned otpless-headless-sdk (Android) or OtplessBM/Core (iOS) version in the OTPLESS Flutter plugin. Use when an upstream native SDK publishes a release, when asked to update the native pin, or when handling a release-train wrapper upgrade — the upstream API goldens enumerate the required bridge work mechanically.
---

# Bumping a native SDK pin

This plugin pins **exact** versions of two native SDKs. A bump is a merchant-visible change (it alters what ships inside their app) and is driven by hub change-flow **rule 3**: SDK publishes → every wrapper pinning it gets a version bump + bridge-compatibility check.

| Platform | File | Pin |
|---|---|---|
| Android | `android/build.gradle` | `io.github.otpless-tech:otpless-headless-sdk:<v>` |
| iOS | `ios/otpless_headless_flutter.podspec` | `s.dependency 'OtplessBM/Core', '<v>'` |

**Never widen to a range** (`^0.9.0`, `~> 2.3`). Exact pins keep merchant builds reproducible and stop a native release from changing behavior without a reviewed PR here (constitution article 5).

## Step 1 — confirm the version actually exists

Do not trust a version number from a chat message or a sibling repo's changelog.

```bash
# Android — Maven Central must return 200
curl -s -o /dev/null -w '%{http_code}\n' \
  https://repo1.maven.org/maven2/io/github/otpless-tech/otpless-headless-sdk/<v>/

# iOS — the pod version must be published
pod trunk info OtplessBM 2>/dev/null | head -30
```

A live trap: android-full published **0.9.0 to Maven Central with no git tag**, and its own `CHANGELOG.md` still files those changes under `## Unreleased`. So "no tag" does not mean "not published", and "in the changelog as unreleased" does not mean "not consumable". Check the artifact repository, which is the only authority on what a merchant can resolve.

## Step 2 — enumerate the bridge work from the upstream goldens

This is the mechanical part, and the reason the sibling repos committed API goldens. Do not read the whole upstream diff.

Locate the upstream checkout **by GitHub repo name**, never by a hardcoded path — the workspace hub's directory layout is not a contract and has already changed once (flat → tiered), which silently broke every `../sibling` reference:

```bash
sibling() {
  repo="$1"
  dir=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  hub=""
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    dir=$(dirname "$dir")
    if [ -f "$dir/.gitmodules" ]; then hub="$dir"; break; fi
  done
  [ -n "$hub" ] || return 1
  key=$(git -C "$hub" config -f .gitmodules --get-regexp 'submodule\..*\.url' \
        | awk -v r="$repo" '$2 ~ ("[:/]" r "\\.git$") {print $1; exit}')
  [ -n "$key" ] || return 1
  rel=$(git -C "$hub" config -f .gitmodules --get "${key%.url}.path") || return 1
  printf '%s/%s\n' "$hub" "$rel"
}

ANDROID_FULL=$(sibling otpless-headless-android-sdk) || {
  echo "upstream not checked out — fall back to the GitHub compare view"; }

git -C "$ANDROID_FULL" diff <old-tag>..<new-tag> -- \
  LongClaw/api/LongClaw.api LongClaw/api/shipped-surface.txt
```

If the resolver fails (a standalone clone with no hub above it), say so and use GitHub's compare view for the two tags — **do not** report "no bridge work required" on the strength of a diff you could not run.

Every removed or changed line in `LongClaw.api` that this plugin's Kotlin bridge touches is required work. Every added line is a **candidate** new capability to expose (a separate decision — use the **bridge-method** skill, and don't smuggle new features into a bump PR).

For iOS, the equivalent baseline is `otpless-headless-iOS-sdk`'s `swift-api-digester` baseline. If it isn't merged upstream yet, fall back to reading the upstream changelog **and** grepping the bridge's call sites:

```bash
grep -oE 'Otpless(SDK|\.shared)\.[a-zA-Z]+' \
  android/src/main/kotlin/com/otpless/headlessflutter/*.kt \
  ios/Classes/*.swift | sort -u
```

Every symbol in that list must still exist upstream at the new version. That grep is the minimum diligence when a golden isn't available.

## Step 3 — check the toolchain floor

A native bump can raise the plugin's floor, which is **breaking for merchants** even though the plugin's own Dart API is unchanged. The 2.0.0 bump to `otpless-headless-sdk:0.9.0` required consumers to move to AGP 8.9.1+ and `compileSdkVersion` 36+ — that belongs in the `### Breaking` changelog section, not buried in an Android bullet.

Check: `minSdkVersion`, `compileSdkVersion`, AGP, Kotlin, and (iOS) `s.ios.deployment_target` and Swift version.

## Step 4 — make the change

1. Edit the pin. **Only the pin** — no opportunistic refactors.
2. Update any bridge call sites the golden diff flagged.
3. Bump the plugin version in `pubspec.yaml`:
   - upstream patch/minor with no bridge change and no floor change → plugin minor
   - any Dart API change, response-type change, or toolchain floor raise → plugin **major**
4. `CHANGELOG.md`: record the new native version **explicitly by number** under the platform heading. `docs-verify.sh` check 2 fails if the pin doesn't appear in the changelog.

## Step 5 — verify (this is where bumps fail)

```bash
make gate
flutter clean && cd example && flutter clean && cd ..   # stale caches link the OLD version
make example-android    # required for an Android pin bump
make example-ios        # required for an iOS pin bump
```

**A green `make gate` proves nothing about a native bump.** `flutter test` never loads the native SDK. The example build is the check. If you skip it, you have not tested the thing you changed — say so explicitly rather than implying otherwise.

Then rung 3 of the **verify** skill: run `example/` on a device and exercise init → start → response. A native bump changes behavior inside the SDK, which no compile step can validate.

## Step 6 — parity

Hub rule 3 fans out: `react-native-headless-sdk` pins the **same two SDKs** as this plugin. A bump here almost always implies one there.

- Check what rn-full currently pins before opening the PR.
- Carry a parity statement: `Parity: ported in react-native-headless-sdk#NN` or `Parity: port ticket <link>`.
- Note in the PR if the two wrappers are now on different native versions — that is a divergence the hub tracks (`docs/PARITY.md` C9/C11), not an acceptable steady state.

## Checklist

- [ ] Version confirmed present in Maven Central / CocoaPods trunk (not just in a changelog)
- [ ] Upstream API golden diffed, or bridge call sites grepped and confirmed present
- [ ] Toolchain floor changes identified and flagged as breaking if raised
- [ ] Pin is exact, not a range
- [ ] Only the pin and required bridge fixes changed — no new features
- [ ] `pubspec.yaml` version bumped per the rules above
- [ ] `CHANGELOG.md` names the new native version explicitly
- [ ] `make gate` green
- [ ] `flutter clean` then the example build for the bumped platform
- [ ] Device smoke of init → start → response
- [ ] Parity statement covering rn-full
