SWIFT_TARGET ?= $(shell uname -m)-apple-macosx14.0
SNAPSHOT_QA_BUILD_DIR ?= $(CURDIR)/.build/snapshot-qa
SNAPSHOT_QA_OUTPUT ?= $(CURDIR)/.build/ui-qa
SNAPSHOT_QA_MODULE_CACHE := $(CURDIR)/.build/snapshot-qa-module-cache
SNAPSHOT_QA_SWIFTPM_MODULE_CACHE := $(CURDIR)/.build/snapshot-qa-swiftpm-module-cache
SWIFTPM_BIN_PATH ?= $(CURDIR)/.build/$(shell uname -m)-apple-macosx/debug
SNAPSHOT_QA_CORE_SOURCES := $(sort $(wildcard Sources/TraceHaloCore/*.swift))
SNAPSHOT_QA_APP_SOURCES := $(sort $(wildcard Sources/TraceHaloApp/*.swift))
SNAPSHOT_QA_CORE_RESOURCE_ACCESSOR := $(SWIFTPM_BIN_PATH)/TraceHaloCore.build/DerivedSources/resource_bundle_accessor.swift
SNAPSHOT_QA_APP_RESOURCE_ACCESSOR := $(SWIFTPM_BIN_PATH)/TraceHaloApp.build/DerivedSources/resource_bundle_accessor.swift

.PHONY: build test app release run snapshot-qa-build snapshot-qa

build:
	swift build

test:
	TRACEHALO_SAFE_TEST_MODE=1 swift test

app:
	zsh scripts/build-app.sh

release:
	zsh scripts/package-release.sh

run:
	swift run TraceHalo

snapshot-qa-build:
	mkdir -p "$(SNAPSHOT_QA_BUILD_DIR)" "$(SNAPSHOT_QA_MODULE_CACHE)" "$(SNAPSHOT_QA_SWIFTPM_MODULE_CACHE)"
	CLANG_MODULE_CACHE_PATH="$(SNAPSHOT_QA_MODULE_CACHE)" SWIFTPM_MODULECACHE_OVERRIDE="$(SNAPSHOT_QA_SWIFTPM_MODULE_CACHE)" swift build --disable-sandbox
	test -f "$(SNAPSHOT_QA_CORE_RESOURCE_ACCESSOR)"
	test -f "$(SNAPSHOT_QA_APP_RESOURCE_ACCESSOR)"
	CLANG_MODULE_CACHE_PATH="$(SNAPSHOT_QA_MODULE_CACHE)" swiftc -disable-sandbox -swift-version 6 -target "$(SWIFT_TARGET)" -parse-as-library -emit-library -static -emit-module -module-name TraceHaloCore -emit-module-path "$(SNAPSHOT_QA_BUILD_DIR)/TraceHaloCore.swiftmodule" $(SNAPSHOT_QA_CORE_SOURCES) "$(SNAPSHOT_QA_CORE_RESOURCE_ACCESSOR)" -o "$(SNAPSHOT_QA_BUILD_DIR)/libTraceHaloCore.a"
	CLANG_MODULE_CACHE_PATH="$(SNAPSHOT_QA_MODULE_CACHE)" swiftc -disable-sandbox -swift-version 6 -target "$(SWIFT_TARGET)" -parse-as-library -D SNAPSHOT_QA -module-name TraceHaloSnapshotQA -I "$(SNAPSHOT_QA_BUILD_DIR)" -L "$(SNAPSHOT_QA_BUILD_DIR)" -lTraceHaloCore $(SNAPSHOT_QA_APP_SOURCES) "$(SNAPSHOT_QA_APP_RESOURCE_ACCESSOR)" Tools/SnapshotQAMain.swift -o "$(SNAPSHOT_QA_BUILD_DIR)/TraceHaloSnapshotQA"

snapshot-qa: snapshot-qa-build
	mkdir -p "$(SNAPSHOT_QA_OUTPUT)"
	TRACEHALO_SNAPSHOT_APP_RESOURCE_BUNDLE="$(SWIFTPM_BIN_PATH)/TraceHalo_TraceHaloApp.bundle" "$(SNAPSHOT_QA_BUILD_DIR)/TraceHaloSnapshotQA" "$(SNAPSHOT_QA_OUTPUT)"
	test -s "$(SNAPSHOT_QA_OUTPUT)/00-system-map-overview.png"
	test -s "$(SNAPSHOT_QA_OUTPUT)/08-input-devices.png"
	test -s "$(SNAPSHOT_QA_OUTPUT)/10-settings.png"
	test -s "$(SNAPSHOT_QA_OUTPUT)/10-settings-no-battery.png"
	test -s "$(SNAPSHOT_QA_OUTPUT)/10-settings-light-en.png"
	test -s "$(SNAPSHOT_QA_OUTPUT)/20-menu-bar-detail-battery.png"
	@echo "Snapshot QA completed: $(SNAPSHOT_QA_OUTPUT)"
