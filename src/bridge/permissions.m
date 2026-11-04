/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

#include "log.h"
#include "permissions.h"

static NSString *const kSlimPermissionPromptedKey = @"SlimshotScreenCapturePrompted";

bool slim_screen_capture_authorized(void) {
    return CGPreflightScreenCaptureAccess();
}

bool slim_screen_capture_prompted(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kSlimPermissionPromptedKey];
}

slim_permission_state_t slim_screen_capture_state(void) {
    if (slim_screen_capture_authorized()) {
        return SLIM_PERMISSION_GRANTED;
    }
    return slim_screen_capture_prompted() ? SLIM_PERMISSION_DENIED
                                          : SLIM_PERMISSION_UNKNOWN;
}

bool slim_screen_capture_request_frontmost(void) {
    if (CGPreflightScreenCaptureAccess()) {
        return true;
    }

    /* CGRequestScreenCaptureAccess shows macOS's own consent dialog exactly
     * once, and that call is also what adds Slimshot to the System Settings
     * list. It must happen while the app is interactive: a request from a
     * background menu bar app is discarded by TCC and leaves the user with a
     * permission list that does not contain Slimshot. */
    NSRunningApplication *current = [NSRunningApplication currentApplication];
    if (!current.active) {
        (void)[current activateWithOptions:NSApplicationActivateAllWindows];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.5];
        while (!current.active && [deadline timeIntervalSinceNow] > 0.0) {
            (void)[[NSRunLoop currentRunLoop]
                runMode:NSDefaultRunLoopMode
                beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
    }

    slim_log("screen capture: requesting access (frontmost=%s)",
             current.active ? "yes" : "no");
    (void)CGRequestScreenCaptureAccess();

    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kSlimPermissionPromptedKey];

    bool granted = CGPreflightScreenCaptureAccess();
    slim_log("screen capture: request finished, authorized=%s", granted ? "yes" : "no");
    return granted;
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
