#!/usr/bin/env python3
"""PreToolUse guard for Edit/Write in the OTPLESS Flutter plugin.

Blocks (exit 2) edits that the repo's protocols say must not happen by hand,
and warns (exit 0 + stderr) on contract-adjacent edits that are legal but
easy to get half-right.

macOS worktree trap
-------------------
This workspace mandates git worktrees under /tmp. On macOS, `os.getcwd()`
resolves to `/private/tmp/...` while the tool's `file_path` may still say
`/tmp/...`. Comparing them naively makes every path look "outside the repo",
which silently disables every guard below — in exactly the layout we use most.
So both sides are realpath()'d before comparison. Test any change to this file
with a manual stdin payload from a /tmp worktree.
"""

import json
import os
import re
import sys

BLOCK = 2
ALLOW = 0


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return ALLOW  # never break the session on a malformed payload

    tool_input = payload.get("tool_input") or {}
    raw_path = tool_input.get("file_path") or ""
    if not raw_path:
        return ALLOW

    repo = os.path.realpath(os.getcwd())
    target = os.path.realpath(raw_path)

    try:
        rel = os.path.relpath(target, repo)
    except ValueError:
        return ALLOW
    if rel.startswith(".."):
        return ALLOW  # outside this repo; not ours to police
    rel = rel.replace(os.sep, "/")

    # ---------------------------------------------------------------- blocks
    if rel == "api/dart-surface.txt":
        sys.stderr.write(
            "BLOCKED: api/dart-surface.txt is a GENERATED golden — never hand-edit it.\n"
            "Change the public API in lib/, then run:\n"
            "    make surface-dump\n"
            "and review the resulting diff line by line before committing.\n"
            "A hand-edited golden defeats the only mechanical public-API check "
            "this repo has (CLAUDE.md constitution article 1).\n"
        )
        return BLOCK

    if rel.startswith("example/"):
        sys.stderr.write(
            f"BLOCKED: {rel} is in example/, which is a TESTBED.\n"
            "CLAUDE.md: never document or refactor example/ unless explicitly asked.\n"
            "If the human explicitly asked for an example-app change, say so and "
            "ask them to confirm before retrying.\n"
        )
        return BLOCK

    if rel == "CHANGELOG.md":
        new = tool_input.get("new_string") or tool_input.get("content") or ""
        old = tool_input.get("old_string") or ""
        # Released sections are immutable history. Detect an edit that targets a
        # version heading other than the top-most (unreleased/current) one.
        released = released_headings(os.path.join(repo, "CHANGELOG.md"))
        touched = {
            h for h in released if h in old or (not old and h in new)
        }
        if touched:
            sys.stderr.write(
                "BLOCKED: this edit touches already-released CHANGELOG history: "
                + ", ".join(sorted(touched))
                + "\nReleased sections are immutable — merchants read them to decide "
                "upgrades.\nAdd a new bullet under the top-most (current/Unreleased) "
                "section instead.\nIf a released entry is genuinely WRONG, say so and "
                "let the human decide.\n"
            )
            return BLOCK

    # ----------------------------------------------------------------- warns
    warn = None
    if rel in (
        "lib/otpless_flutter_method_channel.dart",
        "android/src/main/kotlin/com/otpless/headlessflutter/OtplessFlutterHeadless.kt",
        "ios/Classes/SwiftOtplessFlutterHeadless.swift",
    ):
        warn = (
            f"NOTE: {rel} is one of the THREE bridge layers.\n"
            "A channel method must exist in Dart, Kotlin AND Swift, or be "
            "explicitly rejected on one with a documented reason.\n"
            "Use the bridge-method skill, and run `bash scripts/docs-verify.sh` "
            "(check 3 proves parity) before claiming done."
        )
    elif rel == "pubspec.yaml":
        warn = (
            "NOTE: pubspec.yaml is the SINGLE SOURCE of the plugin version.\n"
            "The podspec derives from it — do not add a version anywhere else.\n"
            "A version change needs a CHANGELOG heading in the same PR."
        )
    elif rel == "android/build.gradle" or rel.endswith(".podspec"):
        warn = (
            f"NOTE: {rel} carries a NATIVE SDK PIN.\n"
            "Bumping it is merchant-visible: use the bump-native-sdk skill, pin an "
            "exact version (never a range), record it in CHANGELOG.md, and run the "
            "example build for that platform."
        )
    elif rel == "Makefile":
        warn = (
            "NOTE: the Makefile holds the CANONICAL gate (GATE_CMD).\n"
            "If you change it, update CLAUDE.md, .github/workflows/build-test.yml "
            "and .claude/skills/verify/SKILL.md in the same edit — "
            "scripts/docs-verify.sh check 6 fails on drift."
        )

    if warn:
        sys.stderr.write(warn + "\n")
    return ALLOW


def released_headings(changelog: str) -> list[str]:
    """Version headings below the top-most one — i.e. shipped history."""
    try:
        with open(changelog, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return []
    headings = [
        ln.strip()
        for ln in lines
        if re.match(r"^##\s+\[?\d+\.\d+", ln.strip())
    ]
    return headings[1:]  # keep the current/top section editable


if __name__ == "__main__":
    sys.exit(main())
