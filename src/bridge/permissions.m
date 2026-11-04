/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

#include "permissions.h"

bool slim_screen_capture_authorized(void) {
    return CGPreflightScreenCaptureAccess();
}

bool slim_request_screen_capture(void) {
    return CGRequestScreenCaptureAccess();
}

void slim_open_screen_capture_settings(void) {
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];

    NSURL *legacy = [NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"];
    if (legacy != nil && [workspace openURL:legacy]) {
        return;
    }

    NSURL *modern = [NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"];
    if (modern != nil) {
        (void)[workspace openURL:modern];
    }
}
