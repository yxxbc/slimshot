/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_CAPTURE_H
#define SLIM_CAPTURE_H

#import <Cocoa/Cocoa.h>

#include "config.h"

typedef NS_ENUM(NSInteger, SlimCaptureMode) {
    SlimCaptureModeFullScreen,
    SlimCaptureModeWindow,
    SlimCaptureModeRegion
};

@interface SlimCaptureController : NSObject
- (instancetype)initWithConfig:(slim_config_t *)config;
- (void)captureMode:(SlimCaptureMode)mode;
- (void)captureMode:(SlimCaptureMode)mode onScreen:(NSScreen *)screen;
@end

#endif /* SLIM_CAPTURE_H */
