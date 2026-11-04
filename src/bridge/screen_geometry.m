/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import "screen_geometry.h"

CGFloat SlimMainScreenHeight(void) {
    NSArray<NSScreen *> *screens = [NSScreen screens];
    if (screens.count == 0) {
        return 0.0;
    }
    return screens.firstObject.frame.size.height;
}

CGRect SlimScreenGlobalCGRect(NSScreen *screen, CGFloat mainHeight) {
    NSRect frame = screen.frame;
    return CGRectMake(frame.origin.x,
                      mainHeight - (frame.origin.y + frame.size.height),
                      frame.size.width, frame.size.height);
}

NSScreen *SlimScreenForDisplayID(CGDirectDisplayID displayID) {
    for (NSScreen *screen in [NSScreen screens]) {
        NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
        if (screenNumber != nil &&
            (CGDirectDisplayID)screenNumber.unsignedIntValue == displayID) {
            return screen;
        }
    }
    return nil;
}

NSScreen *SlimScreenForSCDisplay(SCDisplay *display) {
    if (display == nil) {
        return nil;
    }
    return SlimScreenForDisplayID(display.displayID);
}
