#!/usr/bin/env bash
# Mechanical fact-checks: docs, version single-sourcing, and cross-platform
# bridge parity. Derived from source wherever possible — a check that hardcodes
# the fact it is verifying is theatre.
#
# Analogue of android-lite's scripts/docs-verify.sh. Run by `make gate` and by
# the docs-verify CI workflow.
#
# Exit 1 on any FAIL. WARNs are advisory and do not fail the build.

set -uo pipefail
cd "$(dirname "$0")/.."

fails=0
warns=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }
warn() { echo "WARN: $1"; warns=$((warns + 1)); }

DART_LIB="lib"
KOTLIN="android/src/main/kotlin/com/otpless/headlessflutter/OtplessFlutterHeadless.kt"
SWIFT="ios/Classes/SwiftOtplessFlutterHeadless.swift"
PODSPEC="ios/otpless_headless_flutter.podspec"

# ---------------------------------------------------------------------------
# 1. Version is single-sourced in pubspec.yaml
# ---------------------------------------------------------------------------
PUB_VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | tr -d '\r')"
if [ -z "$PUB_VERSION" ]; then
  fail "could not read version from pubspec.yaml"
else
  pass "pubspec.yaml version = $PUB_VERSION"

  # The podspec must DERIVE the version, not restate it. A literal s.version is
  # how this repo shipped 2.0.0 with a podspec claiming 0.0.1 (PARITY.md C12).
  if grep -qE "^\s*s\.version\s*=\s*['\"][0-9]" "$PODSPEC"; then
    literal="$(grep -oE "s\.version\s*=\s*['\"][^'\"]+" "$PODSPEC" | grep -oE "[0-9][^'\"]*")"
    fail "$PODSPEC hardcodes s.version = '$literal' instead of deriving it from pubspec.yaml (currently $PUB_VERSION). Version must be single-sourced."
  elif grep -q 'pubspec' "$PODSPEC"; then
    pass "podspec derives its version from pubspec.yaml"
  else
    warn "could not determine how $PODSPEC sets s.version"
  fi

  # CHANGELOG must lead with the current version (or an Unreleased section).
  if head -20 CHANGELOG.md | grep -qiE "^##+ +(\[?${PUB_VERSION//./\\.}\]?|unreleased)"; then
    pass "CHANGELOG.md leads with $PUB_VERSION or an Unreleased section"
  else
    fail "CHANGELOG.md has no heading for $PUB_VERSION and no ## Unreleased section"
  fi
fi

# ---------------------------------------------------------------------------
# 2. Native SDK pins are recorded in the changelog
# ---------------------------------------------------------------------------
ANDROID_PIN="$(grep -oE 'io\.github\.otpless-tech:otpless-headless-sdk:[0-9][^"'"'"')]*' android/build.gradle | head -1 | sed 's/.*://')"
IOS_PIN="$(grep -oE "s\.dependency +'OtplessBM/Core', *'[^']+'" "$PODSPEC" | grep -oE "'[0-9][^']*'" | tr -d "'")"

if [ -z "$ANDROID_PIN" ]; then
  fail "could not parse the otpless-headless-sdk pin from android/build.gradle"
else
  if grep -q "$ANDROID_PIN" CHANGELOG.md; then
    pass "Android pin $ANDROID_PIN appears in CHANGELOG.md"
  else
    fail "Android pin $ANDROID_PIN is not mentioned in CHANGELOG.md (rule 3: wrapper bumps are merchant-visible)"
  fi
fi

if [ -z "$IOS_PIN" ]; then
  fail "could not parse the OtplessBM/Core pin from $PODSPEC"
else
  if grep -q "$IOS_PIN" CHANGELOG.md; then
    pass "iOS pin $IOS_PIN appears in CHANGELOG.md"
  else
    fail "iOS pin $IOS_PIN is not mentioned in CHANGELOG.md (rule 3: wrapper bumps are merchant-visible)"
  fi
fi

# ---------------------------------------------------------------------------
# 3. Method-channel parity: every Dart invokeMethod has a native handler
#
# This is the check that matters most for a wrapper. The bridge is a stringly
# typed contract across three languages with no compiler spanning them, so a
# typo or a half-finished port is invisible until a merchant hits it at runtime
# (see PARITY.md B1-B6, and C8 where rn-full declares an iOS method with no
# implementation at all).
# ---------------------------------------------------------------------------
dart_methods="$(grep -rhoE 'invokeMethod\(\s*"[a-zA-Z_]+"' "$DART_LIB" \
  | grep -oE '"[a-zA-Z_]+"' | tr -d '"' | sort -u)"
kotlin_cases="$(grep -oE '^\s*"[a-zA-Z_]+"\s*->' "$KOTLIN" | grep -oE '"[a-zA-Z_]+"' | tr -d '"' | sort -u)"
# Only the `switch call.method` dispatch counts. The file contains other string
# switches (deviceFingerprintMode, AuthEvent) whose cases are NOT channel
# methods, so isolate the dispatch switch by brace depth before scraping.
swift_cases="$(python3 - "$SWIFT" <<'PY'
import re, sys
src = open(sys.argv[1]).read().splitlines()
cases, depth, inside = [], 0, False
for line in src:
    if not inside and re.search(r"switch\s+call\.method", line):
        inside, depth = True, 0
    if inside:
        # Record only cases at the dispatch switch's own level (depth 1).
        # Nested switches (AuthEvent, deviceFingerprintMode) sit deeper and
        # their labels are values, not channel method names.
        m = re.search(r'case\s+"([a-zA-Z_]+)"', line)
        if m and depth == 1:
            cases.append(m.group(1))
        depth += line.count("{") - line.count("}")
        if depth <= 0 and "}" in line:
            inside = False
print("\n".join(sorted(set(cases))))
PY
)"

if [ -z "$dart_methods" ]; then
  fail "found no invokeMethod calls in $DART_LIB/ — the parity check cannot run"
else
  n_dart="$(echo "$dart_methods" | wc -l | tr -d ' ')"
  missing_kotlin=""
  missing_swift=""
  for m in $dart_methods; do
    # The reverse-direction event is invoked BY native, handled IN Dart.
    [ "$m" = "otpless_callback_event" ] && continue
    echo "$kotlin_cases" | grep -qx "$m" || missing_kotlin="$missing_kotlin $m"
    echo "$swift_cases" | grep -qx "$m" || missing_swift="$missing_swift $m"
  done

  if [ -n "$missing_kotlin" ]; then
    fail "Dart calls these channel methods with no Android handler:$missing_kotlin"
  else
    pass "all $n_dart Dart channel methods have an Android handler"
  fi

  if [ -n "$missing_swift" ]; then
    fail "Dart calls these channel methods with no iOS handler:$missing_swift"
  else
    pass "all $n_dart Dart channel methods have an iOS handler"
  fi

  # Native handlers with no Dart caller are dead code — a warning, not a
  # failure: they are usually a removed Dart API whose native side was left.
  for m in $kotlin_cases; do
    echo "$dart_methods" | grep -qx "$m" || warn "Android handles \"$m\" but no Dart code invokes it (unreachable)"
  done
  for m in $swift_cases; do
    echo "$dart_methods" | grep -qx "$m" || warn "iOS handles \"$m\" but no Dart code invokes it (unreachable)"
  done
fi

# ---------------------------------------------------------------------------
# 4. Channel names agree across all three languages
# ---------------------------------------------------------------------------
for name in otpless_headless_flutter otpless_callback_event; do
  d=$(grep -rl "$name" "$DART_LIB" | wc -l | tr -d ' ')
  k=$(grep -c "$name" "$KOTLIN" || true)
  s=$(grep -c "$name" "$SWIFT" || true)
  if [ "$d" -gt 0 ] && [ "$k" -gt 0 ] && [ "$s" -gt 0 ]; then
    pass "channel name \"$name\" present in Dart, Kotlin and Swift"
  else
    fail "channel name \"$name\" missing in one or more layers (dart=$d kotlin=$k swift=$s)"
  fi
done

# ---------------------------------------------------------------------------
# 5. Public surface golden is current
# ---------------------------------------------------------------------------
if python3 scripts/dart_surface.py --check >/dev/null 2>&1; then
  pass "api/dart-surface.txt matches lib/"
else
  fail "api/dart-surface.txt is stale — run 'make surface-dump' and review the diff"
fi

# ---------------------------------------------------------------------------
# 6. Gate drift: every restatement of the gate must match the Makefile
# ---------------------------------------------------------------------------
gate_cmd="$(grep -m1 '^GATE_CMD = ' Makefile | sed 's/^GATE_CMD = //')"
if [ -z "$gate_cmd" ]; then
  fail "could not read GATE_CMD from the Makefile"
else
  for f in CLAUDE.md .github/workflows/build-test.yml .claude/skills/verify/SKILL.md; do
    if [ ! -f "$f" ]; then
      warn "$f does not exist yet — gate-drift check skipped for it"
      continue
    fi
    if grep -qF "$gate_cmd" "$f"; then
      pass "gate line matches the Makefile canonical in $f"
    else
      fail "gate line in $f has drifted from the Makefile's GATE_CMD"
    fi
  done
fi

# ---------------------------------------------------------------------------
# 7. (removed) SDK-GUIDE consistency
#
# Platform documentation now lives in otpless-tech/atlas, not in this repo, so
# there is no local guide to fact-check. The equivalent check did not disappear —
# it moved to Atlas's verify-docs workflow, which this repo's atlas-docs job
# calls on every PR. That job checks out both this PR and Atlas and fails the PR
# if a page this repo owns has fallen behind.
#
# Everything above is source-side and unaffected: it reads only this repo.
# ---------------------------------------------------------------------------

echo
echo "---"
echo "$fails failure(s), $warns warning(s)"
[ "$fails" -eq 0 ] || exit 1
