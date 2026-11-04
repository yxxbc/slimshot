SHELL := /bin/bash

APP_NAME := Slimshot
VERSION ?= 0.1.0
BUILD_NUMBER ?= 1
ARCHS ?=
SPARKLE_DIR ?= vendor/sparkle
SPARKLE_FRAMEWORK := $(SPARKLE_DIR)/Sparkle.framework
HAVE_SPARKLE := $(shell test -d "$(SPARKLE_FRAMEWORK)" && echo 1 || echo 0)
SPARKLE_FEED_URL ?=
SPARKLE_PUBLIC_KEY ?=

MACOSX_DEPLOYMENT_TARGET := 14.0
SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path)
CC := xcrun --sdk macosx clang

BUILD_DIR := build
OBJ_DIR := $(BUILD_DIR)/obj
DIST_DIR := dist
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources

C_SRCS := \
	src/core/config.c \
	src/core/log.c \
	src/core/naming.c \
	src/core/paths.c \
	src/core/plugin.c

M_SRCS := \
	src/main.m \
	src/bridge/about.m \
	src/bridge/app.m \
	src/bridge/capture.m \
	src/bridge/capture_composite.m \
	src/bridge/hotkeys.m \
	src/bridge/output.m \
	src/bridge/overlay_capture.m \
	src/bridge/overlay_controller.m \
	src/bridge/overlay_view.m \
	src/bridge/overlay_windows.m \
	src/bridge/permissions.m \
	src/bridge/plugins.m \
	src/bridge/screen_geometry.m \
	src/bridge/settings.m \
	src/bridge/settings_sidebar.m \
	src/bridge/status_icon.m \
	src/bridge/thumbnail.m

VENDOR_SRCS := src/vendor/cjson/cJSON.c

C_OBJS := $(patsubst %.c,$(OBJ_DIR)/%.o,$(C_SRCS))
M_OBJS := $(patsubst %.m,$(OBJ_DIR)/%.o,$(M_SRCS))
VENDOR_OBJS := $(patsubst %.c,$(OBJ_DIR)/%.o,$(VENDOR_SRCS))
OBJS := $(C_OBJS) $(M_OBJS) $(VENDOR_OBJS)

CFLAGS := -std=c11 -Wall -Wextra -Wpedantic -O2 -g -fno-omit-frame-pointer \
	-mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) -isysroot $(SDKROOT) \
	-Isrc -Isrc/core -Isrc/bridge -Isrc/vendor/cjson $(ARCHS) -MMD -MP
OBJCFLAGS := -fobjc-arc -Wall -Wextra -O2 -g -fno-omit-frame-pointer \
	-mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) -isysroot $(SDKROOT) \
	-Isrc -Isrc/core -Isrc/bridge -Isrc/vendor/cjson $(ARCHS) -MMD -MP
VENDOR_CFLAGS := -std=c11 -O2 -g -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) \
	-isysroot $(SDKROOT) -Isrc/vendor/cjson $(ARCHS) -MMD -MP
TEST_CFLAGS := $(filter-out -MMD -MP,$(CFLAGS))
LDFLAGS := -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) -isysroot $(SDKROOT) \
	$(ARCHS) -framework Cocoa -framework CoreGraphics -framework Foundation \
	-framework Carbon -framework ScreenCaptureKit -framework CoreMedia -framework ImageIO

ifeq ($(HAVE_SPARKLE),1)
SPARKLE_CFLAGS := -DHAVE_SPARKLE=1 -F$(SPARKLE_DIR)
SPARKLE_LDFLAGS := -F$(SPARKLE_DIR) -framework Sparkle \
	-Wl,-rpath,@executable_path/../Frameworks
SPARKLE_APP_DEP := $(SPARKLE_FRAMEWORK) $(SPARKLE_DIR)/LICENSE
else
SPARKLE_CFLAGS := -DHAVE_SPARKLE=0
SPARKLE_LDFLAGS :=
SPARKLE_APP_DEP :=
endif

OBJCFLAGS += $(SPARKLE_CFLAGS)
LDFLAGS += $(SPARKLE_LDFLAGS)

ifeq ($(HAVE_SPARKLE),0)
$(info note: Sparkle.framework not found; run ./scripts/fetch-sparkle.sh to enable updates)
endif

CODESIGN_IDENTITY ?=
CODESIGN_KEYCHAIN ?=

.PHONY: all clean run debug test sign dist logs sparkle

all: $(APP_BUNDLE)

$(OBJ_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ_DIR)/%.o: %.m
	@mkdir -p $(dir $@)
	$(CC) $(OBJCFLAGS) -c $< -o $@

$(VENDOR_OBJS): $(OBJ_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(VENDOR_CFLAGS) -c $< -o $@

$(MACOS_DIR)/$(APP_NAME): $(OBJS)
	@mkdir -p $(MACOS_DIR)
	$(CC) $(OBJS) -o $@ $(LDFLAGS)

OCR_BIN := $(BUILD_DIR)/plugins/ocr/ocr
OCR_SRC := src/plugins/ocr/main.m
OCR_MANIFEST := src/plugins/ocr/manifest.json

EDITOR_BIN := $(BUILD_DIR)/plugins/editor/editor
EDITOR_SRC := src/plugins/editor/main.m
EDITOR_MANIFEST := src/plugins/editor/manifest.json

$(OCR_BIN): $(OCR_SRC)
	@mkdir -p $(dir $@)
	$(CC) $(OBJCFLAGS) $(OCR_SRC) -o $@ \
		-framework Foundation -framework Vision -framework ImageIO -framework CoreGraphics

$(EDITOR_BIN): $(EDITOR_SRC)
	@mkdir -p $(dir $@)
	$(CC) $(OBJCFLAGS) $(EDITOR_SRC) -o $@ \
		-framework Cocoa -framework ImageIO -framework CoreGraphics

$(APP_BUNDLE): $(MACOS_DIR)/$(APP_NAME) resources/Info.plist \
		$(SPARKLE_APP_DEP) \
		resources/icon/Slimshot.icns \
		LICENSE \
		$(OCR_BIN) $(OCR_MANIFEST) \
		$(EDITOR_BIN) $(EDITOR_MANIFEST) \
		resources/en.lproj/Localizable.strings \
		resources/zh-Hans.lproj/Localizable.strings \
		scripts/sign.sh
	@mkdir -p $(RESOURCES_DIR)/en.lproj $(RESOURCES_DIR)/zh-Hans.lproj
	@mkdir -p $(RESOURCES_DIR)/Plugins/ocr $(RESOURCES_DIR)/Plugins/editor
	cp resources/Info.plist $(CONTENTS_DIR)/Info.plist
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" $(CONTENTS_DIR)/Info.plist
	plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" $(CONTENTS_DIR)/Info.plist
	if [ -n "$(SPARKLE_FEED_URL)" ]; then \
		plutil -replace SUFeedURL -string "$(SPARKLE_FEED_URL)" $(CONTENTS_DIR)/Info.plist; \
	fi
	if [ -n "$(SPARKLE_PUBLIC_KEY)" ]; then \
		plutil -replace SUPublicEDKey -string "$(SPARKLE_PUBLIC_KEY)" $(CONTENTS_DIR)/Info.plist; \
	fi
ifeq ($(HAVE_SPARKLE),1)
	@mkdir -p $(CONTENTS_DIR)/Frameworks
	rm -rf "$(CONTENTS_DIR)/Frameworks/Sparkle.framework"
	ditto "$(SPARKLE_FRAMEWORK)" "$(CONTENTS_DIR)/Frameworks/Sparkle.framework"
	cp "$(SPARKLE_DIR)/LICENSE" $(RESOURCES_DIR)/Sparkle-LICENSE
endif
	cp resources/icon/Slimshot.icns $(RESOURCES_DIR)/Slimshot.icns
	cp LICENSE $(RESOURCES_DIR)/LICENSE
	cp $(OCR_BIN) $(RESOURCES_DIR)/Plugins/ocr/ocr
	cp $(OCR_MANIFEST) $(RESOURCES_DIR)/Plugins/ocr/manifest.json
	cp $(EDITOR_BIN) $(RESOURCES_DIR)/Plugins/editor/editor
	cp $(EDITOR_MANIFEST) $(RESOURCES_DIR)/Plugins/editor/manifest.json
	cp resources/en.lproj/Localizable.strings $(RESOURCES_DIR)/en.lproj/
	cp resources/zh-Hans.lproj/Localizable.strings $(RESOURCES_DIR)/zh-Hans.lproj/
	printf 'APPL????' > $(CONTENTS_DIR)/PkgInfo
	plutil -lint $(CONTENTS_DIR)/Info.plist >/dev/null
	CODESIGN_IDENTITY="$(CODESIGN_IDENTITY)" CODESIGN_KEYCHAIN="$(CODESIGN_KEYCHAIN)" \
		./scripts/sign.sh "$(APP_BUNDLE)"

run: all
	open "$(APP_BUNDLE)"

sparkle:
	./scripts/fetch-sparkle.sh

debug: all
	"$(MACOS_DIR)/$(APP_NAME)"

$(BUILD_DIR)/config_test: tests/config_test.c src/core/config.c src/core/naming.c src/core/paths.c $(VENDOR_OBJS)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(TEST_CFLAGS) tests/config_test.c src/core/config.c src/core/naming.c src/core/paths.c \
		$(VENDOR_OBJS) -o $@

$(BUILD_DIR)/plugin_test: tests/plugin_test.c src/core/plugin.c src/core/log.c src/core/paths.c $(VENDOR_OBJS)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(TEST_CFLAGS) tests/plugin_test.c src/core/plugin.c src/core/log.c src/core/paths.c \
		$(VENDOR_OBJS) -o $@

test: $(BUILD_DIR)/config_test $(BUILD_DIR)/plugin_test
	$(BUILD_DIR)/config_test
	$(BUILD_DIR)/plugin_test

sign: $(APP_BUNDLE)
	@if [ -z "$(CODESIGN_IDENTITY)" ]; then \
		echo "CODESIGN_IDENTITY is required" >&2; \
		exit 1; \
	fi
	CODESIGN_IDENTITY="$(CODESIGN_IDENTITY)" CODESIGN_KEYCHAIN="$(CODESIGN_KEYCHAIN)" \
		./scripts/sign.sh "$(APP_BUNDLE)"

dist: all
	VERSION="$(VERSION)" ./scripts/package.sh

logs:
	tail -f "$$HOME/Library/Logs/Slimshot.log"

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR)

-include $(OBJS:.o=.d)
