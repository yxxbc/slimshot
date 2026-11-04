SHELL := /bin/bash

APP_NAME := Slimshot
VERSION ?= 0.1.0
BUILD_NUMBER ?= 1

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
	src/core/paths.c

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
	src/bridge/screen_geometry.m \
	src/bridge/settings.m \
	src/bridge/status_icon.m \
	src/bridge/thumbnail.m

VENDOR_SRCS := src/vendor/cjson/cJSON.c

C_OBJS := $(patsubst %.c,$(OBJ_DIR)/%.o,$(C_SRCS))
M_OBJS := $(patsubst %.m,$(OBJ_DIR)/%.o,$(M_SRCS))
VENDOR_OBJS := $(patsubst %.c,$(OBJ_DIR)/%.o,$(VENDOR_SRCS))
OBJS := $(C_OBJS) $(M_OBJS) $(VENDOR_OBJS)

CFLAGS := -std=c11 -Wall -Wextra -Wpedantic -O2 -g -fno-omit-frame-pointer \
	-mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) -isysroot $(SDKROOT) \
	-Isrc -Isrc/core -Isrc/bridge -Isrc/vendor/cjson -MMD -MP
OBJCFLAGS := -fobjc-arc -Wall -Wextra -O2 -g -fno-omit-frame-pointer \
	-mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) -isysroot $(SDKROOT) \
	-Isrc -Isrc/core -Isrc/bridge -Isrc/vendor/cjson -MMD -MP
VENDOR_CFLAGS := -std=c11 -O2 -g -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) \
	-isysroot $(SDKROOT) -Isrc/vendor/cjson -MMD -MP
TEST_CFLAGS := $(filter-out -MMD -MP,$(CFLAGS))
LDFLAGS := -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) -isysroot $(SDKROOT) \
	-framework Cocoa -framework CoreGraphics -framework Foundation \
	-framework Carbon -framework ScreenCaptureKit -framework CoreMedia -framework ImageIO

CODESIGN_IDENTITY ?=
CODESIGN_KEYCHAIN ?=

.PHONY: all clean run debug test sign dist logs

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

$(APP_BUNDLE): $(MACOS_DIR)/$(APP_NAME) resources/Info.plist \
		resources/icon/Slimshot.icns \
		LICENSE \
		resources/en.lproj/Localizable.strings \
		resources/zh-Hans.lproj/Localizable.strings \
		scripts/sign.sh
	@mkdir -p $(RESOURCES_DIR)/en.lproj $(RESOURCES_DIR)/zh-Hans.lproj
	cp resources/Info.plist $(CONTENTS_DIR)/Info.plist
	cp resources/icon/Slimshot.icns $(RESOURCES_DIR)/Slimshot.icns
	cp LICENSE $(RESOURCES_DIR)/LICENSE
	cp resources/en.lproj/Localizable.strings $(RESOURCES_DIR)/en.lproj/
	cp resources/zh-Hans.lproj/Localizable.strings $(RESOURCES_DIR)/zh-Hans.lproj/
	printf 'APPL????' > $(CONTENTS_DIR)/PkgInfo
	plutil -lint $(CONTENTS_DIR)/Info.plist >/dev/null
	CODESIGN_IDENTITY="$(CODESIGN_IDENTITY)" CODESIGN_KEYCHAIN="$(CODESIGN_KEYCHAIN)" \
		./scripts/sign.sh "$(APP_BUNDLE)"

run: all
	open "$(APP_BUNDLE)"

debug: all
	"$(MACOS_DIR)/$(APP_NAME)"

$(BUILD_DIR)/config_test: tests/config_test.c src/core/config.c src/core/naming.c src/core/paths.c $(VENDOR_OBJS)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(TEST_CFLAGS) tests/config_test.c src/core/config.c src/core/naming.c src/core/paths.c \
		$(VENDOR_OBJS) -o $@

test: $(BUILD_DIR)/config_test
	$(BUILD_DIR)/config_test

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
