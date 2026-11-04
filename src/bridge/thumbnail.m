/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>

#include <math.h>

#include "thumbnail.h"

@interface SlimThumbnailView : NSView
- (instancetype)initWithFrame:(NSRect)frame image:(NSImage *)image filePath:(NSString *)filePath;
@end

@implementation SlimThumbnailView {
    NSImage *_image;
    NSString *_filePath;
    BOOL _dragged;
    NSPoint _dragStart;
    NSRect _initialFrame;
}

- (instancetype)initWithFrame:(NSRect)frame image:(NSImage *)image filePath:(NSString *)filePath {
    self = [super initWithFrame:frame];
    if (self != nil) {
        _image = image;
        _filePath = [filePath copy];
    }
    return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect rect = NSInsetRect(self.bounds, 1.0, 1.0);
    NSBezierPath *background =
        [NSBezierPath bezierPathWithRoundedRect:rect xRadius:10.0 yRadius:10.0];
    [[NSColor.windowBackgroundColor colorWithAlphaComponent:0.96] setFill];
    [background fill];
    [[NSColor.separatorColor colorWithAlphaComponent:0.8] setStroke];
    background.lineWidth = 1.0;
    [background stroke];

    NSRect imageRect = NSInsetRect(self.bounds, 6.0, 6.0);
    [_image drawInRect:imageRect
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1.0
        respectFlipped:YES
                 hints:nil];
}

- (void)mouseDown:(NSEvent *)event {
    (void)event;
    _dragStart = [NSEvent mouseLocation];
    _initialFrame = self.window.frame;
    _dragged = NO;
}

- (void)mouseDragged:(NSEvent *)event {
    (void)event;
    NSPoint point = [NSEvent mouseLocation];
    CGFloat dx = point.x - _dragStart.x;
    CGFloat dy = point.y - _dragStart.y;
    if (fabs(dx) > 2.0 || fabs(dy) > 2.0) {
        _dragged = YES;
    }
    NSRect frame = _initialFrame;
    frame.origin.x += dx;
    frame.origin.y += dy;
    [self.window setFrameOrigin:frame.origin];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    if (!_dragged && _filePath.length > 0) {
        NSURL *url = [NSURL fileURLWithPath:_filePath];
        (void)[[NSWorkspace sharedWorkspace] openURL:url];
        dispatch_async(dispatch_get_main_queue(), ^{
            slim_thumbnail_hide();
        });
    }
}

- (void)rightMouseDown:(NSEvent *)event {
    (void)event;
    dispatch_async(dispatch_get_main_queue(), ^{
        slim_thumbnail_hide();
    });
}

@end

@interface SlimThumbnailController : NSObject
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, assign) NSUInteger generation;
- (void)close;
@end

static SlimThumbnailController *gCurrent;
static NSUInteger gGeneration;

@implementation SlimThumbnailController

- (void)close {
    [self.panel orderOut:nil];
    [self.panel close];
    self.panel = nil;
    if (gCurrent == self) {
        gCurrent = nil;
    }
}

@end

void slim_thumbnail_hide(void) {
    SlimThumbnailController *current = gCurrent;
    gCurrent = nil;
    [current close];
}

void slim_thumbnail_show(CGImageRef image, NSScreen *screen, NSString *filePath, int seconds) {
    if (image == NULL) {
        return;
    }
    slim_thumbnail_hide();

    size_t pixelWidth = CGImageGetWidth(image);
    size_t pixelHeight = CGImageGetHeight(image);
    if (pixelWidth == 0 || pixelHeight == 0) {
        return;
    }

    CGFloat maxWidth = 240.0;
    CGFloat maxHeight = 160.0;
    CGFloat scale = MIN(1.0, MIN(maxWidth / (CGFloat)pixelWidth,
                                 maxHeight / (CGFloat)pixelHeight));
    CGFloat imageWidth = MAX(80.0, (CGFloat)pixelWidth * scale);
    CGFloat imageHeight = MAX(60.0, (CGFloat)pixelHeight * scale);
    NSSize contentSize = NSMakeSize(imageWidth + 12.0, imageHeight + 12.0);

    NSImage *nsImage = [[NSImage alloc] initWithCGImage:image
                                                   size:NSMakeSize((CGFloat)pixelWidth,
                                                                   (CGFloat)pixelHeight)];
    SlimThumbnailView *view =
        [[SlimThumbnailView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width,
                                                            contentSize.height)
                                           image:nsImage
                                        filePath:filePath];

    NSPanel *panel =
        [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, contentSize.width,
                                                        contentSize.height)
                                  styleMask:(NSWindowStyleMaskBorderless |
                                             NSWindowStyleMaskNonactivatingPanel)
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
    panel.opaque = NO;
    panel.backgroundColor = [NSColor clearColor];
    panel.hasShadow = YES;
    panel.level = NSFloatingWindowLevel;
    panel.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                                NSWindowCollectionBehaviorStationary |
                                NSWindowCollectionBehaviorFullScreenAuxiliary |
                                NSWindowCollectionBehaviorIgnoresCycle);
    panel.hidesOnDeactivate = NO;
    panel.becomesKeyOnlyIfNeeded = YES;
    panel.releasedWhenClosed = NO;
    panel.contentView = view;

    NSScreen *target = (screen != nil) ? screen : [NSScreen mainScreen];
    NSRect visible = target.visibleFrame;
    NSRect frame = panel.frame;
    CGFloat margin = 20.0;
    frame.origin.x = NSMaxX(visible) - frame.size.width - margin;
    frame.origin.x = MAX(NSMinX(visible) + margin, frame.origin.x);
    frame.origin.y = NSMinY(visible) + margin;
    [panel setFrame:frame display:NO];
    [panel orderFrontRegardless];

    SlimThumbnailController *controller = [[SlimThumbnailController alloc] init];
    controller.panel = panel;
    controller.generation = ++gGeneration;
    gCurrent = controller;

    if (seconds > 0) {
        NSUInteger generation = controller.generation;
        __weak SlimThumbnailController *weakController = controller;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)seconds * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            SlimThumbnailController *strongController = weakController;
            if (strongController != nil && strongController.generation == generation) {
                if (gCurrent == strongController) {
                    gCurrent = nil;
                }
                [strongController close];
            }
        });
    }
}
