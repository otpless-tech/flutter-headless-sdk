---
name: release
description: Cut a release of the otpless_headless_flutter plugin — version decision, changelog promotion, verification, publish to pub.dev, and tag. Use when asked to release, bump the plugin version, publish to pub, or prepare a release PR.
---

# Releasing otpless_headless_flutter

The published artifact is a **pub.dev package**. Unlike the Android SDKs there is no signing step, but publishing is **irreversible** — pub.dev does not allow deleting or replacing a published version, only retracting it. Get it right before you push the button.

## Version is single-sourced

`pubspec.yaml` `version:` is the **only** place the version is set. The podspec derives it at parse time; `scripts/docs-verify.sh` check 1 fails if a literal version reappears there. Do not add a version constant anywhere else.

## 1. Decide the version

| Change | Bump |
|---|---|
| Dart signature/param rename, enum reorder, channel method rename, removed API | **major** |
| Raised Flutter/Dart floor, or a native pin that raises AGP/compileSdk/iOS target | **major** |
| New response type a merchant's `switch` may not handle | **major** (2.0.0 treated it so) |
| New method, new optional parameter, native pin with no floor change | minor |
| Bug fix, doc-only, internal refactor | patch |

When in doubt it's breaking. A merchant discovering a break at runtime costs far more than a major version number.

## 2. Promote the changelog

- Retitle the working section to the release version with the date, matching existing style: `## 2.0.0 (27th July 2026)`.
- Confirm every merged PR since the last release has a bullet. `git log --no-merges --oneline <last-tag>..HEAD`.
- Confirm both native pins are named explicitly by version.
- Confirm breaking changes are under `### Breaking` **and** that the README migration section covers them.
- Never edit an already-released section (a hook blocks it).

## 3. Verify — everything, both platforms

```bash
make gate
flutter clean && (cd example && flutter clean)
make example-android
make example-ios
```

Then run `example/` on a real device/simulator and exercise init → start → response on **both** platforms. A release is the one time rung 3 of the **verify** skill is mandatory rather than advised: `flutter test` has never loaded the native SDKs this package exists to wrap.

## 4. Dry-run the publish

```bash
flutter pub publish --dry-run
```

Read the file list it prints. Things that must **not** ship:
- `example/` build output, `.dart_tool/`, local `.env`/credentials
- anything matched by `.pubignore` that isn't actually ignored

Check the reported package size against the previous release (see the **size-review** skill). An unexplained jump means something leaked into the package.

## 5. Publish

```bash
flutter pub publish
```

Requires a pub.dev account with publish rights on `otpless_headless_flutter`. `.claude/settings.json` **denies** this command for agents — publishing is a human action. If you are an agent: stop here, report that everything up to this point is green, and hand off.

## 6. Tag and push

```bash
git tag -a <version> -m "otpless_headless_flutter <version>"
git push origin <version>
```

Tag **after** a successful publish, so the tag always means "this is on pub.dev".

Related trap: android-full published `0.9.0` to Maven Central with **no git tag**, leaving no way to know from the repo what shipped. Don't reproduce that here — the tag is how the release train and the hub's `bump-native-sdk` protocol identify what a wrapper can pin.

## 7. Fan out (hub rule 3)

This plugin is a leaf — nothing pins it. But a release here is the moment to check the reverse direction: are its native pins current?

Query the remotes directly — no checkout and no assumption about where the
workspace hub keeps things:

```bash
git ls-remote --tags --sort=-v:refname \
  git@github.com:otpless-tech/otpless-headless-android-sdk.git | head -3
git ls-remote --tags --sort=-v:refname \
  git@github.com:otpless-tech/otpless-headless-iOS-sdk.git | head -3
```

Caveat learned the hard way: android-full has published to Maven Central **without
tagging** (0.9.0), so a missing tag does not prove a version is unavailable. For
Android, confirm against Maven Central as in the **bump-native-sdk** skill's
step 1; the tag list is a convenience, not the authority.

If either upstream has moved, note it in the release PR so it's scheduled rather than forgotten. Also state whether `react-native-headless-sdk` — which pins the same two natives — is on the same versions; divergence there is tracked in the hub's `docs/PARITY.md`.

## Checklist

- [ ] Version decided per the table and set **only** in `pubspec.yaml`
- [ ] Changelog section retitled with version + date; every PR represented
- [ ] Native pins named explicitly; breaking changes under `### Breaking`
- [ ] README migration notes cover every break
- [ ] `make gate` green
- [ ] `flutter clean` then `make example-android` **and** `make example-ios`
- [ ] Device smoke on both platforms
- [ ] `flutter pub publish --dry-run` file list and size reviewed
- [ ] Published (human) → then tagged and pushed
- [ ] Upstream pin currency and rn-full parity noted
