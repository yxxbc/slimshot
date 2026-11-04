/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_HOTKEYS_H
#define SLIM_HOTKEYS_H

#import <Cocoa/Cocoa.h>

#include "capture.h"

@interface SlimHotKeyManager : NSObject
- (instancetype)initWithHandler:(void (^)(SlimCaptureMode mode))handler;
- (BOOL)registerHotKey:(NSString *)specification
                  mode:(SlimCaptureMode)mode
                 error:(NSString **)error;
- (void)unregisterAll;
@end

#endif /* SLIM_HOTKEYS_H */
