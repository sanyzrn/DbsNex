# Mirrors the CI jobs one-to-one so `make check` reproduces the pipeline
# locally. Every CI job below reduces to one of these targets.

.PHONY: check check-dart check-ui check-client check-backend \
        fmt clean bootstrap backend-dev migrate

# Each Dart package resolves independently, and every lockfile is committed.
#
# A root pub workspace was tried and reverted once, and tried again when an
# audit recommended it (NEX-24). It is not available to this repo. A workspace
# forces one resolution across every member, and two of the five members
# declare `flutter: sdk: flutter`, which a standalone Dart SDK cannot satisfy —
# so `dart pub get` fails, and that command is precisely how the dart-packages
# CI job proves core and data carry zero Flutter dependency. The job never
# installs Flutter; that *is* the assertion.
#
# Splitting it — one workspace for the pure-Dart trio, one for the Flutter pair
# — does not work either. Workspaces cannot nest:
#
#     The file `./packages/pubspec.yaml` is located in a directory between the
#     workspace root at `.` and a workspace package at `./packages/ui`. But is
#     not a member of the workspace.
#
# So the choice is one workspace or none, and one workspace costs a guarantee
# worth more than unified resolution. What the audit was actually reaching for —
# reproducibility — is solved by committing all five lockfiles, which costs
# nothing and is done. This target is the orchestration layer.
bootstrap:
	cd packages/core && dart pub get
	cd packages/data && dart pub get
	cd packages/ai   && flutter pub get
	cd packages/ui   && flutter pub get
	cd apps/client   && flutter pub get
	cd apps/backend  && npm ci
	cd apps/feedback-worker && npm ci

# Pure Dart packages: proves core and data carry zero Flutter dependency.
check-dart:
	cd packages/core && dart analyze --fatal-infos && dart test
	cd packages/data && dart analyze --fatal-infos && dart test

# nex_ai is not one of those two, and putting it in that list broke this whole
# file. It carries a Flutter dependency, so its dev dependency is
# `flutter_test` and `dart test` cannot run it: the command exits 65 with
# "Could not find package `test`", and because `check` chains these targets,
# every one after it — ui, client, backend — never ran either. So `make check`
# failed on a clean checkout, for everyone, while CI was green: CI has always
# run this package with `flutter test` (the flutter-ai-package job). The
# header at the top of this file promises to mirror CI one-to-one, and this
# line was the place it did not.
check-ai:
	cd packages/ai && flutter analyze --fatal-infos && flutter test

check-ui:
	cd packages/ui && flutter analyze --fatal-infos && flutter test

check-client:
	cd apps/client && flutter analyze --fatal-infos && flutter test

check-backend:
	cd apps/backend && npm run typecheck && npm run lint && npm test

# The feedback worker is deployed separately and was verified by nothing: no
# make target, and no CI job matched `apps/feedback-worker/` either. Its nine
# tests passed the whole time and never gated anything.
check-worker:
	cd apps/feedback-worker && npm run typecheck && npm test

check: check-dart check-ai check-ui check-client check-backend check-worker

fmt:
	dart format apps/client packages
	cd apps/backend && npx prettier --write "src/**/*.ts"

backend-dev:
	cd apps/backend && npm run start:dev

migrate:
	cd apps/backend && npm run migrate:dev

clean:
	flutter clean || true
	rm -rf apps/backend/dist apps/backend/node_modules
