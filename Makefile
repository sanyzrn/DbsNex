# Mirrors the CI jobs one-to-one so `make check` reproduces the pipeline
# locally. Every CI job below reduces to one of these targets.

.PHONY: check check-dart check-ui check-client check-backend \
        fmt clean bootstrap backend-dev migrate

# Each Dart package resolves independently. A root pub workspace was tried and
# reverted: it forces one resolution across every member, so `dart pub get` in
# packages/core pulled in apps/client and failed with "nex_ui requires the
# Flutter SDK" — which destroys the guarantee the dart-packages CI job exists to
# prove. This target is the orchestration layer instead.
bootstrap:
	cd packages/core && dart pub get
	cd packages/data && dart pub get
	cd packages/ai   && dart pub get
	cd packages/ui   && flutter pub get
	cd apps/client   && flutter pub get
	cd apps/backend  && npm ci

# Pure Dart packages: proves core and data carry zero Flutter dependency.
check-dart:
	cd packages/core && dart analyze --fatal-infos && dart test
	cd packages/data && dart analyze --fatal-infos && dart test
	cd packages/ai   && dart analyze --fatal-infos && dart test

check-ui:
	cd packages/ui && flutter analyze --fatal-infos && flutter test

check-client:
	cd apps/client && flutter analyze --fatal-infos && flutter test

check-backend:
	cd apps/backend && npm run typecheck && npm run lint && npm test

check: check-dart check-ui check-client check-backend

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
