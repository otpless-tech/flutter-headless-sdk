---
name: docs-sync
description: Sync docs/SDK-GUIDE.md and CHANGELOG.md with code changes in the OTPLESS Flutter plugin. Use whenever lib/, android/ or ios/ has changed and documentation must catch up, when running the docs-sync CI job, when asked to update the docs or changelog, or after merging any PR that touches the plugin.
---

# Syncing docs to code

Two artifacts, two different jobs:

| File | Audience | Content |
|---|---|---|
| `docs/SDK-GUIDE.md` | agents and maintainers | exhaustive, current-state description of the code. No history. |
| `CHANGELOG.md` | merchants (and the public-docs automation) | per-release behavior changes, in merchant language. Append-only history. |

`docs/.doc-sync-state` holds the commit SHA the docs were last synced to. Doc-sync commits carry the `[docs-sync]` marker and contain **only** doc files — never a source change.

## Procedure

### 1. Establish the range

```bash
last=$(tr -d '[:space:]' < docs/.doc-sync-state)
git log --no-merges --oneline "$last..HEAD" -- lib android ios pubspec.yaml api
git diff --stat "$last..HEAD" -- lib android ios pubspec.yaml api
```

If `.doc-sync-state` is missing or points at an unreachable commit, do not guess — say so and ask which SHA to use as the baseline.

### 2. Read the actual diff, not the commit subjects

**This is the step that matters.** A commit titled "iOS parity" tells you nothing about what a merchant now observes. Read the diff. For every changed hunk, ask: does this change something a merchant can see, or is it internal?

Never restate a commit subject as if it were documented behavior. That is how a changelog ends up claiming a feature that shipped as a no-op — `startOnetap` and `sendUserAuthEvent` were documented as working on iOS while both returned immediately without doing anything.

### 3. Update `docs/SDK-GUIDE.md`

The guide describes **current state**. Rewrite the affected sections; don't append "as of 2.0.0" notes.

Sections that go stale most often:
- the channel-method table (one row per method: Dart signature → channel name → Android behavior → iOS behavior)
- **platform asymmetries** — every method that behaves differently or no-ops on one platform. If you add a method, its platform story is mandatory.
- the response contract (`responseType` / `response` / `statusCode`) and how it's marshalled
- native pins and the toolchain floor they impose
- the quirks section

§ numbers are **stable identifiers** other files reference. Never renumber; add `§9.3`-style sub-sections instead.

### 4. Update `CHANGELOG.md`

- One bullet per merged PR, phrased as **user-visible behavior**, with the PR number.
- Add to the **top-most** section only. Released sections are immutable history — a hook blocks edits to them. If a released entry is genuinely wrong, say so and let a human decide.
- Group under `### Breaking` / `### Android` / `### iOS` / `### Repo & tooling`, matching the existing style.
- **Native pin bumps must name the version explicitly** — `docs-verify.sh` check 2 fails otherwise.
- **Toolchain floor raises go under `### Breaking`**, not buried in a platform bullet. A merchant who can't build is a broken merchant even if our Dart API is unchanged.
- **Removed or renamed public API: mark, never delete.** The changelog must keep saying the old name existed and what replaced it, permanently. A merchant on an old version reads this to plan an upgrade; deleting the row makes the break undiscoverable.

Merchant-language test: would a Flutter developer who has never seen this repo understand what changes for them? "Refactored request parsing" fails. "`start()` now accepts `code`, `extras`, `requestId` and `deviceFingerprintMode`" passes.

### 5. Stamp and verify

```bash
git rev-parse HEAD > docs/.doc-sync-state
bash scripts/docs-verify.sh
```

The mechanical checks must pass. They catch: version drift across pubspec/podspec/changelog, an unrecorded native pin, a stale surface golden, and gate drift. They cannot catch a plausible-but-false sentence — that is your job.

### 6. Commit

```
[docs-sync] sync documentation to <sha>
```

Doc files only. If you found a code bug while reading the diff (likely — reading diffs carefully is how the `timeout`/`loginUri` dead parameters were found), **do not fix it here**. Note it in the PR body and open a separate issue or PR.

## The public-docs connection

The merchant-facing docs at otpless.com/docs are drafted from this repo's merged PRs by an automation that reads `CHANGELOG.md` as its primary signal. A vague or wrong changelog bullet becomes a vague or wrong public doc page. Phrase for that audience.

## Traps

- **The CI job may have already done this.** Check for an open `docs/sync` PR before starting; duplicating it wastes review.
- **A stale `docs/sync` PR is worse than none.** If one exists but points at an older SHA than HEAD, update or close it — android-full carries exactly this (`#88` targeting a superseded commit).
- **Don't document `example/`.** It is a testbed.
- **Don't invent § numbers** for content that belongs in an existing section.
