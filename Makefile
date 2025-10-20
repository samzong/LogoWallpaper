SCHEME ?= LogoWallpaper
DESTINATION ?= platform=macOS
ARCHIVE_PATH ?= build/LogoWallpaper.xcarchive
DERIVED_DATA_PATH ?= build

.PHONY: help build release test test-all clean clean-build archive

help:
	@echo "Usage: make <target>"
	@echo "Available targets:"
	@echo "  build       Build Debug configuration for $(SCHEME)."
	@echo "  release     Build Release configuration for $(SCHEME)."
	@echo "  test        Run unit tests only (LogoWallpaperTests)."
	@echo "  test-all    Run the full test suite, including UI tests."
	@echo "  clean       Clean derived build artifacts for $(SCHEME)."
	@echo "  clean-build Clean then perform a fresh Debug build."
	@echo "  archive     Produce a Release archive at $(ARCHIVE_PATH)."

build:
	xcodebuild -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) build

release:
	xcodebuild -scheme $(SCHEME) -configuration Release -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) build

test:
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) -only-testing:$(SCHEME)Tests test

test-all:
	xcodebuild -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) test

clean:
	xcodebuild -scheme $(SCHEME) clean

archive:
	mkdir -p $(dir $(ARCHIVE_PATH))
	xcodebuild -scheme $(SCHEME) -configuration Release -archivePath $(ARCHIVE_PATH) archive
