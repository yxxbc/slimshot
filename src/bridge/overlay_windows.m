/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

#include <unistd.h>

#import "overlay_internal.h"

@implementation SlimWindowInfo
@end

NSArray<SlimWindowInfo *> *SlimBuildWindowInfos(SCShareableContent *content) {
    NSMutableArray<SlimWindowInfo *> *result = [NSMutableArray array];
    if (content == nil) {
        return result;
    }

    NSMutableDictionary<NSNumber *, SCWindow *> *windowsByID = [NSMutableDictionary dictionary];
    for (SCWindow *window in content.windows) {
        windowsByID[@(window.windowID)] = window;
    }

    CFArrayRef windowList = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    if (windowList == NULL) {
        return result;
    }

    CFIndex count = CFArrayGetCount(windowList);
    for (CFIndex i = 0; i < count; i++) {
        NSDictionary *info =
            (__bridge NSDictionary *)CFArrayGetValueAtIndex(windowList, i);

        NSNumber *layer = info[(__bridge NSString *)kCGWindowLayer];
        if (layer == nil || layer.integerValue != 0) {
            continue;
        }
        NSNumber *pid = info[(__bridge NSString *)kCGWindowOwnerPID];
        if (pid != nil && pid.intValue == getpid()) {
            continue;
        }
        NSNumber *alpha = info[(__bridge NSString *)kCGWindowAlpha];
        if (alpha != nil && alpha.doubleValue < 0.01) {
            continue;
        }
        NSNumber *windowNumber = info[(__bridge NSString *)kCGWindowNumber];
        if (windowNumber == nil) {
            continue;
        }
        SCWindow *scWindow = windowsByID[windowNumber];
        if (scWindow == nil || !scWindow.onScreen || scWindow.windowLayer != 0) {
            continue;
        }

        NSDictionary *boundsDict = info[(__bridge NSString *)kCGWindowBounds];
        if (boundsDict == nil) {
            continue;
        }
        CGRect cgFrame = CGRectZero;
        if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)boundsDict,
                                                    &cgFrame)) {
            continue;
        }
        if (cgFrame.size.width < 2.0 || cgFrame.size.height < 2.0) {
            continue;
        }

        SlimWindowInfo *windowInfo = [[SlimWindowInfo alloc] init];
        windowInfo.window = scWindow;
        windowInfo.globalRect = cgFrame;

        NSString *owner = info[(__bridge NSString *)kCGWindowOwnerName];
        if (owner.length == 0) {
            owner = scWindow.owningApplication.applicationName;
        }
        windowInfo.appName = (owner != nil) ? owner : @"";

        NSString *title = info[(__bridge NSString *)kCGWindowName];
        if (title.length == 0) {
            title = scWindow.title;
        }
        windowInfo.title = (title != nil) ? title : @"";

        [result addObject:windowInfo];
    }
    CFRelease(windowList);
    return result;
}

@implementation SlimOverlayWindow
- (BOOL)canBecomeKeyWindow {
    return YES;
}
- (BOOL)canBecomeMainWindow {
    return NO;
}
@end
