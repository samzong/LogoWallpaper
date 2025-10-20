APP_NAME ?= LogoWallpaper
SCHEME ?= $(APP_NAME)
PROJECT ?= LogoWallpaper.xcodeproj
DESTINATION ?= platform=macOS
BUILD_DIR ?= build
DERIVED_DATA_PATH ?= $(BUILD_DIR)
CONFIGURATION ?= Release
ARCHIVE_PATH ?= $(BUILD_DIR)/$(APP_NAME).xcarchive
SWIFTLINT ?= swiftlint

ARCHES := x86_64 arm64
DMG_VOLUME_NAME = $(APP_NAME)
DMG_LABEL_x86_64 = Intel
DMG_LABEL_arm64 = Apple Silicon

# Version information
GIT_COMMIT := $(shell git rev-parse --short HEAD)
ifndef VERSION
VERSION := $(shell git describe --tags --always)
endif

ifndef MARKETING_SEMVER
MARKETING_SEMVER := $(shell \
	VERSION_STR="$(VERSION)"; \
	CLEAN=$$(echo $$VERSION_STR | sed -E 's/^v//; s/-.*//'); \
	if echo $$CLEAN | grep -Eq '^[0-9]+(\.[0-9]+){0,2}$$'; then \
		echo $$CLEAN; \
	else \
		echo 0.0.0; \
	fi)
endif

ifndef BUILD_NUMBER
BUILD_NUMBER := $(shell git rev-list --count HEAD)
endif

# Homebrew tap settings
HOMEBREW_TAP_REPO = homebrew-tap
CASK_TOKEN = logo-wallpaper
CASK_FILE = Casks/$(CASK_TOKEN).rb
BRANCH_NAME = update-$(CASK_TOKEN)-$(MARKETING_SEMVER)

.PHONY: help build release test test-all clean clean-build archive dmg check-arch version update-homebrew lint $(foreach arch,$(ARCHES),build-$(arch))

help:
	@echo "Usage: make <target>"
	@echo "Targets:"
	@echo "  build           Build Debug configuration (runs unit tests first)."
	@echo "  release         Build Release configuration."
	@echo "  test            Run unit tests only (LogoWallpaperTests)."
	@echo "  test-all        Run the full test suite, including UI tests."
	@echo "  clean           Clean derived build artifacts for $(SCHEME)."
	@echo "  clean-build     Clean then perform a fresh Debug build."
	@echo "  archive         Produce a Release archive at $(ARCHIVE_PATH)."
	@echo "  dmg             Produce notarization-ready DMGs for Intel and Apple Silicon."
	@echo "  check-arch      Validate architecture slices in archived binaries."
	@echo "  version         Print resolved version metadata."
	@echo "  update-homebrew GH_PAT=token  Update samzong/homebrew-tap cask."
	@echo "  lint            Run SwiftLint using .swiftlint.yml."

build: test
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) build

release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) build

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) -only-testing:$(SCHEME)Tests test

test-all:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) test

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean

clean-build: clean build

archive:
	mkdir -p $(dir $(ARCHIVE_PATH))
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -archivePath $(ARCHIVE_PATH) archive

define archive_path
$(BUILD_DIR)/$(APP_NAME)-$(1).xcarchive
endef

define build_archive_for_arch
	@echo "==> Build $(1) architecture archive..."
	xcodebuild clean archive \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-archivePath $(call archive_path,$(1)) \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY="-" \
		DEVELOPMENT_TEAM="" \
		CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) \
		MARKETING_VERSION=$(MARKETING_SEMVER) \
		ARCHS="$(1)" \
		OTHER_CODE_SIGN_FLAGS="--options=runtime"
endef

define build_target_template
.PHONY: build-$(1)
build-$(1):
	$(call build_archive_for_arch,$(1))
endef
$(foreach arch,$(ARCHES),$(eval $(call build_target_template,$(arch))))

dmg: $(foreach arch,$(ARCHES),build-$(arch))
	@for arch in $(ARCHES); do \
		echo "==> Export $$arch archive..."; \
		xcodebuild -exportArchive \
			-archivePath "$(BUILD_DIR)/$(APP_NAME)-$$arch.xcarchive" \
			-exportPath "$(BUILD_DIR)/$$arch" \
			-exportOptionsPlist "$(CURDIR)/exportOptions.plist"; \
		rm -rf "$(BUILD_DIR)/tmp-$$arch"; \
		mkdir -p "$(BUILD_DIR)/tmp-$$arch"; \
		cp -R "$(BUILD_DIR)/$$arch/$(APP_NAME).app" "$(BUILD_DIR)/tmp-$$arch/"; \
		echo "==> Self-sign $$arch application..."; \
		codesign --force --deep --sign - "$(BUILD_DIR)/tmp-$$arch/$(APP_NAME).app"; \
		ln -s /Applications "$(BUILD_DIR)/tmp-$$arch/Applications"; \
		case "$$arch" in \
			arm64) vol_label="$(DMG_LABEL_arm64)";; \
			*) vol_label="$(DMG_LABEL_x86_64)";; \
		esac; \
		hdiutil create -volname "$$(printf "%s (%s)" "$(DMG_VOLUME_NAME)" "$$vol_label")" \
			-srcfolder "$(BUILD_DIR)/tmp-$$arch" \
			-ov -format UDZO \
			"$(BUILD_DIR)/$(APP_NAME)-$$arch.dmg"; \
		rm -rf "$(BUILD_DIR)/tmp-$$arch" "$(BUILD_DIR)/$$arch"; \
	done
	@$(MAKE) --no-print-directory check-arch
	@echo "==> All DMG files have been created:"
	@for arch in $(ARCHES); do \
		echo "    - $$arch DMG: $(BUILD_DIR)/$(APP_NAME)-$$arch.dmg"; \
	done
	@echo ""
	@echo "DMGs are self-signed; users may need to approve them in System Settings."

check-arch:
	@echo "==> Check application architecture compatibility..."
	@for arch in $(ARCHES); do \
		BINARY="$(call archive_path,$$arch)/Products/Applications/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)"; \
		if [ -f "$$BINARY" ]; then \
			echo "==> Inspecting $$arch slice"; \
			lipo -info "$$BINARY"; \
			if lipo -info "$$BINARY" | grep -q "$$arch"; then \
				echo "✅ $$arch archive contains $$arch slice"; \
			else \
				echo "❌ $$arch archive missing $$arch slice"; \
				exit 1; \
			fi; \
		else \
			echo "❌ Archive for $$arch not found at $$BINARY"; \
			exit 1; \
		fi; \
	done

version:
	@echo "Version:             $(VERSION)"
	@echo "Marketing SemVer:    $(MARKETING_SEMVER)"
	@echo "Build Number:        $(BUILD_NUMBER)"
	@echo "Git Commit:          $(GIT_COMMIT)"

lint:
	@command -v $(SWIFTLINT) >/dev/null 2>&1 || { echo "❌ SwiftLint not installed. Install via 'brew install swiftlint'."; exit 127; }
	@$(SWIFTLINT) --config .swiftlint.yml

update-homebrew:
	@echo "==> Starting Homebrew cask update process..."
	@if [ -z "$(GH_PAT)" ]; then \
		echo "❌ Error: GH_PAT environment variable is required"; \
		exit 1; \
	fi

	@echo "==> Current version information:"
	@echo "    - VERSION: $(VERSION)"
	@echo "    - MARKETING_SEMVER: $(MARKETING_SEMVER)"

	@echo "==> Preparing working directory..."
	@rm -rf tmp && mkdir -p tmp

	@echo "==> Downloading DMG files..."
	@curl -L -o tmp/$(APP_NAME)-x86_64.dmg "https://github.com/samzong/$(APP_NAME)/releases/download/v$(MARKETING_SEMVER)/$(APP_NAME)-x86_64.dmg"
	@curl -L -o tmp/$(APP_NAME)-arm64.dmg "https://github.com/samzong/$(APP_NAME)/releases/download/v$(MARKETING_SEMVER)/$(APP_NAME)-arm64.dmg"

	@echo "==> Calculating SHA256 checksums..."
	@X86_64_SHA256=$$(shasum -a 256 tmp/$(APP_NAME)-x86_64.dmg | cut -d ' ' -f 1) && echo "    - x86_64 SHA256: $$X86_64_SHA256"
	@ARM64_SHA256=$$(shasum -a 256 tmp/$(APP_NAME)-arm64.dmg | cut -d ' ' -f 1) && echo "    - arm64 SHA256: $$ARM64_SHA256"

	@echo "==> Cloning Homebrew tap repository..."
	@cd tmp && git clone https://$(GH_PAT)@github.com/samzong/$(HOMEBREW_TAP_REPO).git
	@cd tmp/$(HOMEBREW_TAP_REPO) && echo "    - Creating new branch: $(BRANCH_NAME)" && git checkout -b $(BRANCH_NAME)

	@echo "==> Updating cask file..."
	@cd tmp/$(HOMEBREW_TAP_REPO) && \
	X86_64_SHA256=$$(shasum -a 256 ../$(APP_NAME)-x86_64.dmg | cut -d ' ' -f 1) && \
	ARM64_SHA256=$$(shasum -a 256 ../$(APP_NAME)-arm64.dmg | cut -d ' ' -f 1) && \
	sed -i '' 's/version "[^"]*"/version "$(MARKETING_SEMVER)"/' $(CASK_FILE) && \
	if grep -q "on_arm" $(CASK_FILE); then \
		sed -i '' '/on_arm/,/end/{s/sha256 "[^"]*"/sha256 "'"$$ARM64_SHA256"'"/;}' $(CASK_FILE); \
		sed -i '' '/on_intel/,/end/{s/sha256 "[^"]*"/sha256 "'"$$X86_64_SHA256"'"/;}' $(CASK_FILE); \
	else \
		echo "❌ Unknown cask format, cannot update SHA256 values"; \
		exit 1; \
	fi

	@echo "==> Checking for changes..."
	@cd tmp/$(HOMEBREW_TAP_REPO) && \
	if ! git diff --quiet $(CASK_FILE); then \
		echo "    - Changes detected, creating pull request..."; \
		git add $(CASK_FILE); \
		git config user.name "GitHub Actions"; \
		git config user.email "actions@github.com"; \
		git commit -m "chore: update $(APP_NAME) to v$(MARKETING_SEMVER)"; \
		git push -u origin $(BRANCH_NAME); \
		pr_data=$$(printf '{"title":"chore: update %s to v%s","body":"Auto-generated PR\\n- Version: %s\\n- x86_64 SHA256: %s\\n- arm64 SHA256: %s","head":"%s","base":"main"}' \
			"$(APP_NAME)" "$(MARKETING_SEMVER)" "$(MARKETING_SEMVER)" "$$X86_64_SHA256" "$$ARM64_SHA256" "$(BRANCH_NAME)"); \
		curl -X POST \
			-H "Authorization: token $(GH_PAT)" \
			-H "Content-Type: application/json" \
			https://api.github.com/repos/samzong/$(HOMEBREW_TAP_REPO)/pulls \
			-d "$$pr_data"; \
		echo "✅ Pull request created successfully"; \
	else \
		echo "❌ No changes detected in cask file"; \
		exit 1; \
	fi

	@echo "==> Cleaning up temporary files..."
	@rm -rf tmp
	@echo "✅ Homebrew cask update process completed"
