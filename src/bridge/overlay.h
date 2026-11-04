/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_OVERLAY_H
#define SLIM_OVERLAY_H

#import <Cocoa/Cocoa.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

typedef NS_ENUM(NSInteger, SlimOverlayMode) {
    SlimOverlayModeRegion,
    SlimOverlayModeWindow
};

@interface SlimScreenCapture : NSObject
- (instancetype)initWithScreen:(NSScreen *)screen image:(CGImageRef)image;
@property (nonatomic, strong, readonly) NSScreen *screen;
@property (nonatomic, readonly) CGImageRef image;
@end

@interface SlimOverlayPluginAction : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
+ (instancetype)actionWithIdentifier:(NSString *)identifier title:(NSString *)title;
@end

@interface SlimOverlayController : NSObject
- (instancetype)initWithMode:(SlimOverlayMode)mode
              screenCaptures:(NSArray<SlimScreenCapture *> *)captures
            shareableContent:(SCShareableContent *)content
                 startScreen:(NSScreen *)startScreen
               pluginActions:(NSArray<SlimOverlayPluginAction *> *)pluginActions
                    onRegion:(void (^)(NSArray<SlimScreenCapture *> *captures,
                                       CGRect selectionGlobal,
                                       NSString *pluginID))onRegion
                    onWindow:(void (^)(SCWindow *window))onWindow
                    onCancel:(void (^)(void))onCancel;
- (void)show;
- (void)cancel;
@end

#endif /* SLIM_OVERLAY_H */
