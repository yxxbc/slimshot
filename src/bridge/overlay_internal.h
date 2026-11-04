/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 *
 * Private interfaces shared by the overlay modules. Public clients use overlay.h.
 */

#ifndef SLIM_OVERLAY_INTERNAL_H
#define SLIM_OVERLAY_INTERNAL_H

#import <Cocoa/Cocoa.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

#import "overlay.h"

@interface SlimScreenCapture ()
@property (nonatomic, assign) NSRect localRect;
@property (nonatomic, strong) NSImage *nsImage;
@end

@interface SlimWindowInfo : NSObject
@property (nonatomic, strong) SCWindow *window;
@property (nonatomic, assign) CGRect globalRect;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *title;
@end

/* Windows are in front-to-back order to match visual hit-testing. */
NSArray<SlimWindowInfo *> *SlimBuildWindowInfos(SCShareableContent *content);

@interface SlimOverlayWindow : NSWindow
@end

@class SlimOverlayView;

@protocol SlimOverlayViewDelegate <NSObject>
- (void)overlayView:(SlimOverlayView *)view
     didSelectRegion:(NSRect)rect
           pluginID:(NSString *)pluginID;
- (void)overlayView:(SlimOverlayView *)view didSelectWindow:(SCWindow *)window;
- (void)overlayViewDidCancel:(SlimOverlayView *)view;
- (void)overlayViewDidChangeSelection:(SlimOverlayView *)view;
@end

@interface SlimOverlayView : NSView
- (instancetype)initWithFrame:(NSRect)frame
                         mode:(SlimOverlayMode)mode
                     captures:(NSArray<SlimScreenCapture *> *)captures
                      windows:(NSArray<SlimWindowInfo *> *)windows
                     delegate:(id<SlimOverlayViewDelegate>)delegate;
- (void)setDisplayScale:(CGFloat)scale;
- (void)setHintRect:(NSRect)rect;
- (void)setReferenceCg:(CGRect)rect;
- (void)setSelectionBounds:(NSRect)bounds;
- (void)setSelectionRect:(NSRect)rect;
- (void)setShowsToolbar:(BOOL)flag;
- (void)setShowsHint:(BOOL)flag;
- (void)setPluginActions:(NSArray<SlimOverlayPluginAction *> *)actions;
- (NSRect)selectionRect;
- (CGRect)selectionGlobalRect;
- (CGRect)referenceCg;
@end

#endif /* SLIM_OVERLAY_INTERNAL_H */
