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
# on it. Regenerated whenever project.yml changes.
Crossroads.xcodeproj: project.yml
	xcodegen generate

.PHONY: app
app: Crossroads.xcodeproj
	xcodebuild -project Crossroads.xcodeproj -scheme Crossroads -configuration Debug build
