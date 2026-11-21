# The macOS version: CrossroadsCore, and later the app.
# The specs are shared and checked from the repository root (make check).

# Command Line Tools ships swift-testing but does not always hand SwiftPM the
# macro plugin that goes with it, so point the compiler at it when it's there.
# A full Xcode install needs none of this, and the flag does no harm.
TESTING_PLUGINS := $(shell xcode-select -p)/usr/lib/swift/host/plugins/testing
ifneq ($(wildcard $(TESTING_PLUGINS)),)
SWIFT_TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS)
endif

.PHONY: test
test:
	swift test $(SWIFT_TEST_FLAGS)

# The app project is generated, never hand-edited, so a rebase cannot conflict
# on it. Always regenerated: the file list comes from the App folder, so adding
# or removing a source has to be picked up too, not just a project.yml change.
.PHONY: project
project:
	@xcodegen generate --quiet

# Build products go next to the project, not into DerivedData, so `make run`
# and `make install` always know where the app is.
BUILD_DIR := build
APP := $(BUILD_DIR)/Build/Products/Debug/Crossroads.app

.PHONY: app
app: project
	xcodebuild -project Crossroads.xcodeproj -scheme Crossroads \
		-configuration Debug -derivedDataPath $(BUILD_DIR) build

# Restart it, so a rebuild replaces the copy that is already running. Waiting
# for the old one to go matters: `open` fails with -600 if it is still on its
# way out.
.PHONY: run
run: app
	@pkill -x Crossroads 2>/dev/null || true
	@for _ in $$(seq 25); do pgrep -x Crossroads >/dev/null || break; sleep 0.2; done
	open $(APP)

# Draws the panel with made-up data straight to a PNG for the README. Renders
# offscreen, so it needs no screen recording permission and never shows a real
# calendar.
.PHONY: screenshot
screenshot: app
	@pkill -x Crossroads 2>/dev/null || true
	@for _ in $$(seq 25); do pgrep -x Crossroads >/dev/null || break; sleep 0.2; done
	$(APP)/Contents/MacOS/Crossroads --screenshot ../assets
