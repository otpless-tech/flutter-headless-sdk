#!/usr/bin/env python3
"""Extract the public Dart surface of lib/ as a stable, sorted text golden.

This is the Flutter analogue of android-lite's binary-compatibility-validator
dump: a committed file that makes every public-API change show up as a reviewed
diff instead of slipping out in a release. It is intentionally toolchain-free
(pure stdlib, no `dart`/`analyzer` dependency) so it runs identically on a dev
machine, in CI, and in a hook.

What counts as public surface, and why:
  * Anything whose name starts with `_` is private to its library in Dart, so it
    is excluded — merchants cannot reach it.
  * `lib/*.dart` only. Files under `lib/src/` would also be private-by-convention,
    but this package has none; if one is added, it is excluded here too.
  * Enum *values* are part of the contract: `.name` is what crosses the method
    channel (see lib/models.dart -> toMap()), so reordering or renaming a value
    is a wire-format break. Values are therefore listed, in source order.
  * Parameter names are part of the contract because Dart callers use named
    arguments. Types are normalised for whitespace only, never reordered.

Usage:
  python3 scripts/dart_surface.py            # print surface to stdout
  python3 scripts/dart_surface.py --check     # diff against the committed golden
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
LIB = REPO / "lib"
GOLDEN = REPO / "api" / "dart-surface.txt"

# A declaration keyword we care about, at class-body or top level.
TYPE_DECL = re.compile(
    r"^\s*(?:abstract\s+)?(?P<kind>class|enum|mixin|extension|typedef)\s+"
    r"(?P<name>[A-Za-z_$][\w$]*)"
)
# Member/function signature: optional modifiers, a type, a name, then '('.
MEMBER = re.compile(
    r"^\s*(?P<mods>(?:static|final|const|late|external|@\w+\s*)*)\s*"
    r"(?P<sig>[\w$<>,\s\[\]?.]*?)\s*(?P<name>[A-Za-z_$][\w$]*)\s*\("
)
# Field/getter without parens: `final Foo? bar;` / `Foo get bar =>`
FIELD = re.compile(
    r"^\s*(?P<mods>(?:static\s+|final\s+|const\s+|late\s+)*)"
    r"(?P<type>[\w$<>,\s\[\]?.]+?)\s+(?P<name>[A-Za-z_$][\w$]*)\s*(?:;|=[^=>]|=>)"
)


def strip_comments(text: str) -> str:
    """Remove // and /* */ comments without touching string literals."""
    out = []
    i, n = 0, len(text)
    quote: str | None = None
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if quote:
            if ch == "\\":
                out.append(text[i : i + 2])
                i += 2
                continue
            if ch == quote:
                quote = None
            out.append(ch)
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            out.append(ch)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def logical_lines(src: str) -> list[str]:
    """Join physical lines into logical declarations.

    Dart wraps freely: a field can be `final String?\\n    locale;` and a method
    signature can span four lines. Parsing physical lines silently drops both
    (a missing field looks identical to a removed field in the golden), so
    accumulate until we hit `;`, `{`, or `}` at paren/bracket depth 0.
    """
    out: list[str] = []
    buf: list[str] = []
    depth = 0
    for raw in src.splitlines():
        line = raw.strip()
        if not line:
            if not buf:
                out.append("")
            continue
        buf.append(line)
        for ch in line:
            if ch in "([":
                depth += 1
            elif ch in ")]":
                depth -= 1
        if depth <= 0 and re.search(r"[;{}]\s*$", line):
            out.append(" ".join(buf))
            buf = []
            depth = 0
    if buf:
        out.append(" ".join(buf))
    return out


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def is_public(name: str) -> bool:
    return bool(name) and not name.startswith("_")


def parse(path: pathlib.Path) -> list[str]:
    src = strip_comments(path.read_text(encoding="utf-8"))
    lines = logical_lines(src)
    entries: list[str] = []

    depth = 0
    container: str | None = None
    container_depth = 0
    enum_buf: list[str] | None = None

    for raw in lines:
        # Annotations join onto the logical line (`@visibleForTesting final x = ...`);
        # strip them so the declaration underneath still matches.
        line = re.sub(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)+", "", raw).rstrip()
        if not line.strip():
            depth += line.count("{") - line.count("}")
            continue

        # Collect enum values across lines until the closing brace.
        if enum_buf is not None:
            chunk = line.split("}")[0]
            enum_buf.append(chunk)
            if "}" in line:
                body = norm(" ".join(enum_buf))
                vals = [v.strip() for v in body.split(",") if v.strip()]
                # Drop any trailing member declarations inside enhanced enums.
                vals = [v for v in vals if re.fullmatch(r"[A-Za-z_$][\w$]*", v)]
                if container:
                    entries.append(f"enum {container} {{ {', '.join(vals)} }}")
                enum_buf = None
                container = None
            depth += line.count("{") - line.count("}")
            continue

        m = TYPE_DECL.match(line)
        if m and depth == 0:
            kind, name = m.group("kind"), m.group("name")
            if not is_public(name):
                container = None
            elif kind == "enum":
                container = name
                enum_buf = [line.split("{", 1)[1]] if "{" in line else []
                if "}" in line and "{" in line:
                    body = norm(line.split("{", 1)[1].split("}")[0])
                    vals = [v.strip() for v in body.split(",") if v.strip()]
                    entries.append(f"enum {name} {{ {', '.join(vals)} }}")
                    enum_buf = None
                    container = None
                depth += line.count("{") - line.count("}")
                continue
            elif kind == "typedef":
                entries.append(norm(line.rstrip(";")))
                container = None
            else:
                base = ""
                for kw in (" extends ", " implements ", " with ", " on "):
                    if kw in line:
                        base = " " + norm(line.split("{")[0].split(name, 1)[1])
                        break
                entries.append(f"{kind} {name}{base}".rstrip())
                container = name
                container_depth = depth
            depth += line.count("{") - line.count("}")
            continue

        # Members of a public class, one level in.
        if container and depth == container_depth + 1:
            mm = MEMBER.match(line)
            if mm and is_public(mm.group("name")):
                name = mm.group("name")
                sig = norm(mm.group("sig"))
                # Constructors: `ClassName(` / `const ClassName(`
                params = line.split("(", 1)[1]
                params = params.split(")")[0] if ")" in params else params + "..."
                mods = norm(mm.group("mods"))
                prefix = f"{mods} " if mods and not mods.startswith("@") else ""
                if name == container and not sig:
                    entries.append(f"  {container}({norm(params)})")
                elif sig:
                    entries.append(f"  {prefix}{sig} {name}({norm(params)})")
            else:
                fm = FIELD.match(line)
                if fm and is_public(fm.group("name")):
                    t = norm(fm.group("type"))
                    head = t.split()[0] if t.split() else ""
                    if head and head not in ("return", "await", "if", "for"):
                        mods = norm(fm.group("mods"))
                        prefix = f"{mods} " if mods else ""
                        entries.append(f"  {prefix}{t} {fm.group('name')}")

        depth += line.count("{") - line.count("}")
        if container is not None and depth <= container_depth:
            container = None

    return entries


def build() -> str:
    out: list[str] = []
    for path in sorted(LIB.rglob("*.dart")):
        rel = path.relative_to(REPO).as_posix()
        entries = parse(path)
        if not entries:
            continue
        out.append(f"# {rel}")
        out.extend(entries)
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="diff against the golden")
    args = ap.parse_args()

    surface = build()
    if not args.check:
        sys.stdout.write(surface)
        return 0

    if not GOLDEN.exists():
        sys.stderr.write(
            f"FAIL: golden {GOLDEN.relative_to(REPO)} is missing.\n"
            "      Generate it with: make surface-dump\n"
        )
        return 1

    expected = GOLDEN.read_text(encoding="utf-8")
    if expected == surface:
        print(f"PASS: public Dart surface matches {GOLDEN.relative_to(REPO)}")
        return 0

    import difflib

    diff = difflib.unified_diff(
        expected.splitlines(keepends=True),
        surface.splitlines(keepends=True),
        fromfile=f"{GOLDEN.relative_to(REPO)} (committed)",
        tofile="lib/ (actual)",
    )
    sys.stderr.write(
        "FAIL: public Dart surface changed but the golden was not updated.\n\n"
    )
    sys.stderr.writelines(diff)
    sys.stderr.write(
        "\n\nIf this change is intended: run `make surface-dump`, review the diff\n"
        "line by line, and commit it IN THE SAME PR. A public-surface change also\n"
        "needs a CHANGELOG entry and (if breaking) a major version bump — see\n"
        "CLAUDE.md constitution article 1.\n"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
