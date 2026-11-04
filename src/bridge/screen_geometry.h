/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_SCREEN_GEOMETRY_H
#define SLIM_SCREEN_GEOMETRY_H

#import <Cocoa/Cocoa.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

/* Height of the main screen (the one with the menu bar), in points. */
CGFloat SlimMainScreenHeight(void);

/* Convert NSScreen.frame (AppKit, origin bottom-left) to CG global coordinates. */
CGRect SlimScreenGlobalCGRect(NSScreen *screen, CGFloat mainHeight);

/* Match a CG display / SCK display back to the NSScreen with the same display ID. */
NSScreen *SlimScreenForDisplayID(CGDirectDisplayID displayID);
NSScreen *SlimScreenForSCDisplay(SCDisplay *display);

#endif /* SLIM_SCREEN_GEOMETRY_H */
