/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_SETTINGS_SIDEBAR_H
#define SLIM_SETTINGS_SIDEBAR_H

#import <Cocoa/Cocoa.h>

@interface SlimSettingsSidebarItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbolName;
+ (instancetype)itemWithTitle:(NSString *)title symbolName:(NSString *)symbolName;
@end

@interface SlimSettingsSidebarController : NSViewController
@property (nonatomic, copy) NSArray<SlimSettingsSidebarItem *> *items;
@property (nonatomic, copy) void (^selectionHandler)(NSInteger row);
- (void)selectRow:(NSInteger)row;
@end

#endif /* SLIM_SETTINGS_SIDEBAR_H */
