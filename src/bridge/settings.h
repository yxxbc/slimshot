/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>

#include "config.h"

@interface SettingsWindowController : NSWindowController
- (instancetype)initWithConfig:(slim_config_t *)config;
- (void)present;
@end
