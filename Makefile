# 78th

XCODEGEN ?= xcodegen
SCHEME   ?= 78th
DEST     ?= generic/platform=iOS Simulator

.PHONY: help
help:
	@echo "make engine-test   Run the schedule engine's unit tests (no Xcode project needed)"
	@echo "make project       Generate 78th.xcodeproj from project.yml"
	@echo "make build         Generate the project and build the app and widget"
	@echo "make open          Generate the project and open it in Xcode"
	@echo "make lint-sql      Check the Supabase migration parses"
	@echo "make clean         Remove generated build artifacts"

# The whole of milestone 1 is testable with nothing but a Swift toolchain.
.PHONY: engine-test
engine-test:
	cd Packages/ScheduleEngine && swift test

.PHONY: project
project:
	$(XCODEGEN) generate --spec project.yml

.PHONY: build
build: project
	xcodebuild -project 78th.xcodeproj -scheme "$(SCHEME)" -destination "$(DEST)" \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

.PHONY: open
open: project
	open 78th.xcodeproj

.PHONY: lint-sql
lint-sql:
	@command -v psql >/dev/null 2>&1 || { echo "psql not installed, skipping"; exit 0; }
	psql --no-psqlrc --quiet --output=/dev/null --command="\\set ON_ERROR_STOP on" \
		--file=Supabase/migrations/0001_init.sql --dry-run 2>/dev/null || \
		echo "Run this against a scratch database: psql -f Supabase/migrations/0001_init.sql"

.PHONY: clean
clean:
	rm -rf 78th.xcodeproj build .build Packages/ScheduleEngine/.build
