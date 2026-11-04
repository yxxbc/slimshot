/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_PLUGINS_H
#define SLIM_PLUGINS_H

#import <Cocoa/Cocoa.h>

#include "plugin.h"

@interface SlimPlugin : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, assign) slim_plugin_type_t type;
@property (nonatomic, copy) NSString *execPath;
@property (nonatomic, assign) int timeoutMs;
@property (nonatomic, assign) BOOL builtin;
@end

@interface SlimPluginManager : NSObject
+ (instancetype)sharedManager;
- (void)reload;
- (NSArray<SlimPlugin *> *)plugins;
- (SlimPlugin *)pluginWithIdentifier:(NSString *)identifier;
- (BOOL)hasPostProcessPlugins;
- (BOOL)hasCapture;
- (void)noteCaptureWithPath:(NSString *)path
                      width:(int)width
                     height:(int)height
                      scale:(double)scale
                     source:(NSString *)source;
- (void)runPlugin:(SlimPlugin *)plugin
       completion:(void (^)(BOOL ok, NSString *message))completion;
@end

#endif /* SLIM_PLUGINS_H */
