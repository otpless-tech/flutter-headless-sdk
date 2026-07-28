.PHONY: help gate test analyze format format-fix surface-dump surface-check docs-verify example-android example-ios clean

# ---------------------------------------------------------------------------
# The canonical verification gate. THIS IS THE SINGLE SOURCE OF TRUTH.
#
# CLAUDE.md, .github/workflows/build-test.yml and .claude/skills/verify all
# restate this command list; scripts/docs-verify.sh check 6 fails the build if
# any of those copies drift from the line below. Change it HERE first.
# ---------------------------------------------------------------------------
GATE_CMD = dart format --output=none --set-exit-if-changed lib test && flutter analyze --fatal-infos lib test && flutter test

help:
	@echo "make gate           full verification gate (run before claiming any change works)"
	@echo "make deps           flutter pub get (gate prerequisite)"
	@echo "make test           flutter test only"
	@echo "make analyze        flutter analyze --fatal-infos lib test"
	@echo "make format         check formatting (no writes)"
	@echo "make format-fix     apply dart format"
	@echo "make surface-dump   regenerate api/dart-surface.txt (review the diff!)"
	@echo "make surface-check   diff public Dart surface against the golden"
	@echo "make docs-verify    mechanical doc/changelog fact-checks"
	@echo "make example-android build the example app against the pinned native SDKs"
	@echo "make example-ios     build the example app for iOS (no codesign)"

# `deps` is a prerequisite, not part of GATE_CMD: without a resolved package
# config, `dart format` picks a different default language version and reports
# every file as needing reformatting, so the gate fails on a fresh clone or a
# new worktree for a reason that has nothing to do with the diff.
gate: deps
	$(GATE_CMD)
	python3 scripts/dart_surface.py --check
	bash scripts/docs-verify.sh

deps:
	flutter pub get

test:
	flutter test

analyze:
	flutter analyze --fatal-infos lib test

format:
	dart format --output=none --set-exit-if-changed lib test

format-fix:
	dart format lib test

surface-dump:
	python3 scripts/dart_surface.py > api/dart-surface.txt
	@echo "Regenerated api/dart-surface.txt — REVIEW THE DIFF before committing."
	@git --no-pager diff --stat api/dart-surface.txt || true

surface-check:
	python3 scripts/dart_surface.py --check

docs-verify:
	bash scripts/docs-verify.sh

# Native example builds are the only thing that proves the Kotlin/Swift bridge
# compiles against the pinned native SDKs — `flutter test` never touches it.
example-android:
	cd example && flutter build apk --debug

example-ios:
	cd example && flutter build ios --no-codesign --debug

clean:
	flutter clean
	cd example && flutter clean
