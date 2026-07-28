---
name: size-review
description: Size review for the OTPLESS Flutter plugin — what the package and its pinned native SDKs cost a merchant's app. Use on every PR touching lib/, android/ or ios/, when running the size-check CI job, when asked about plugin or app size, or before adding any dependency.
---

# Size review

Merchants ship this plugin inside their app. Two numbers matter, and they are very different in magnitude:

| Number | What it is | Typical scale |
|---|---|---|
| Package payload | what `flutter pub publish` uploads — Dart + Kotlin + Swift **source** | tens of KB |
| Delivered footprint | the pinned native SDKs, compiled into the merchant's APK/IPA | **hundreds of KB** |

The plugin's own code is nearly free. **The native pins dominate**, and this repo controls them. That is where size review actually bites.

## Measuring

### Package payload

```bash
flutter pub publish --dry-run
```

Prints every file that would ship, plus a total. Review the file **list**, not just the number: the common regression is accidentally shipping `example/` build output or a stray artifact, which shows up as a sudden jump.

### Delivered footprint

```bash
cd example && flutter build apk --release
find build -name '*-release.apk' -exec wc -c {} \;
```

Compare against the same measurement on `main`. The CI `size-check` job posts both numbers on every PR touching `lib/`, `android/` or `ios/`.

For attribution on Android:

```bash
cd example && flutter build apk --release --analyze-size
```

That reports per-library contribution — the fastest way to see how much of the APK is `otpless-headless-sdk` versus everything else.

## Reviewing a diff for size

Ask, in order:

1. **Did a native pin change?** This is the only change that moves the number materially. Get the upstream's own size figures — android-lite and android-full maintain an AAR size table in their `CHANGELOG.md`, which tells you the delta before you build anything. Record it in this repo's changelog bullet.
2. **New runtime dependency in `pubspec.yaml`?** Default answer is no (constitution article 5). The plugin has exactly two runtime deps by design. A new one lands in every merchant app and every security scan. Dev dependencies are free — they don't ship.
3. **New files in `lib/`?** Negligible in bytes, but check they belong in the published package rather than in `example/` or `test/`.
4. **New transitive Android dependency** added in `android/build.gradle`? Same scrutiny as a pub dependency — it *does* ship.
5. **Anything added to the package that isn't source?** Images, fixtures, docs beyond README/CHANGELOG. Use `.pubignore` to keep them out.

## What is NOT a size finding

- Dart source size in the tens of KB. Don't spend review time here.
- `example/` changes — the testbed doesn't ship. (It's still the right place to *measure*.)
- Test files — excluded from the package.
- Documentation. `docs/SDK-GUIDE.md` is large and that's fine; keep it out of the published package via `.pubignore` and move on.

## Reporting

State both numbers with the delta and its cause:

```
Package payload: 48.2 KB → 48.4 KB (+0.2 KB, new Dart method)
Example release APK: 21.4 MB → 21.4 MB (unchanged — no native pin change)
```

If a native pin moved, attribute the delta to it explicitly and cite the upstream's size table. An unexplained delta is the finding: it means something shipped that nobody decided to ship.

Size is enforced by review, not by a byte gate — the CI job is advisory. A regression with a clear justification recorded in the changelog is acceptable; a silent one is not.
