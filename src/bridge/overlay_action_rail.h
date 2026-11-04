/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_OVERLAY_ACTION_RAIL_H
#define SLIM_OVERLAY_ACTION_RAIL_H

#import <Cocoa/Cocoa.h>

#import "overlay.h"

/*
 * Vertical action rail shown next to a region selection. Icon-only so it
 * can hold several plugin slots without widening; overflow opens a menu.
 */
@interface SlimOverlayActionRail : NSView
@property (nonatomic, copy) void (^pluginHandler)(NSString *identifier);
@property (nonatomic, copy) void (^captureHandler)(void);
@property (nonatomic, copy) void (^cancelHandler)(void);
- (void)setPluginActions:(NSArray<SlimOverlayPluginAction *> *)actions;
- (NSSize)preferredSize;
@end

#endif /* SLIM_OVERLAY_ACTION_RAIL_H */
