/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

#import "overlay_internal.h"

@implementation SlimScreenCapture

- (instancetype)initWithScreen:(NSScreen *)screen image:(CGImageRef)image {
    self = [super init];
    if (self != nil) {
        _screen = screen;
        if (image != NULL) {
            _image = CGImageRetain(image);
            _nsImage = [[NSImage alloc]
                initWithCGImage:image
                           size:NSMakeSize((CGFloat)CGImageGetWidth(image),
                                           (CGFloat)CGImageGetHeight(image))];
        }
    }
    return self;
}

- (void)dealloc {
    if (_image != NULL) {
        CGImageRelease(_image);
    }
}

@end

@implementation SlimOverlayPluginAction
+ (instancetype)actionWithIdentifier:(NSString *)identifier title:(NSString *)title {
    SlimOverlayPluginAction *action = [[self alloc] init];
    action.identifier = identifier;
    action.title = title;
    return action;
}
@end
