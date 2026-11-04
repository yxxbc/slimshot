/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>

#include <math.h>

#include "plugins.h"
#include "thumbnail.h"

@interface SlimThumbnailView : NSView
- (instancetype)initWithFrame:(NSRect)frame
                        image:(NSImage *)image
                     filePath:(NSString *)filePath
                      plugins:(NSArray<SlimPlugin *> *)plugins;
@end

@implementation SlimThumbnailView {
    NSImage *_image;
    NSString *_filePath;
    NSArray<SlimPlugin *> *_plugins;
    NSRect _imageRect;
    BOOL _dragged;
    NSPoint _dragStart;
    NSRect _initialFrame;
}

- (instancetype)initWithFrame:(NSRect)frame
                        image:(NSImage *)image
                     filePath:(NSString *)filePath
                      plugins:(NSArray<SlimPlugin *> *)plugins {
    self = [super initWithFrame:frame];
    if (self != nil) {
        _image = image;
        _filePath = [filePath copy];
        _plugins = [plugins copy];

        CGFloat bottom = (_plugins.count > 0) ? 34.0 : 6.0;
        _imageRect = NSMakeRect(6.0, bottom, frame.size.width - 12.0,
                                frame.size.height - bottom - 6.0);

        if (_plugins.count > 0) {
            CGFloat x = 8.0;
            NSUInteger visible = MIN(_plugins.count, (NSUInteger)4);
            for (NSUInteger i = 0; i < visible; i++) {
                SlimPlugin *plugin = _plugins[i];
                NSButton *button =
                    [NSButton buttonWithTitle:plugin.name
                                       target:self
                                       action:@selector(pluginButtonClicked:)];
                button.bezelStyle = NSBezelStyleRounded;
                button.controlSize = NSControlSizeSmall;
                button.image = [NSImage imageWithSystemSymbolName:plugin.iconName
                                          accessibilityDescription:plugin.name];
                button.imagePosition = NSImageOnly;
                button.contentTintColor = [NSColor labelColor];
                button.identifier = plugin.identifier;
                button.toolTip = plugin.name;
                button.frame = NSMakeRect(x, 6.0, 30.0, 22.0);
                [self addSubview:button];
                x += 34.0;
            }
            if (_plugins.count > visible) {
                NSButton *more =
                    [NSButton buttonWithTitle:NSLocalizedString(@"overlay.more", nil)
                                       target:self
                                       action:@selector(overflowPressed:)];
                more.bezelStyle = NSBezelStyleRounded;
                more.controlSize = NSControlSizeSmall;
                more.image = [NSImage imageWithSystemSymbolName:@"ellipsis"
                                        accessibilityDescription:
                                            NSLocalizedString(@"overlay.more", nil)];
                more.imagePosition = NSImageOnly;
                more.contentTintColor = [NSColor labelColor];
                more.toolTip = NSLocalizedString(@"overlay.more", nil);
                more.frame = NSMakeRect(x, 6.0, 30.0, 22.0);
                [self addSubview:more];
            }
        }
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

    if (_plugins.count > 0) {
        NSBezierPath *divider = [NSBezierPath bezierPath];
        [divider moveToPoint:NSMakePoint(6.0, 34.0)];
        [divider lineToPoint:NSMakePoint(self.bounds.size.width - 6.0, 34.0)];
        [[NSColor.separatorColor colorWithAlphaComponent:0.6] setStroke];
        divider.lineWidth = 1.0;
        [divider stroke];
    }

    [_image drawInRect:_imageRect
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
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (!_dragged && NSPointInRect(point, _imageRect) && _filePath.length > 0) {
        NSURL *url = [NSURL fileURLWithPath:_filePath];
        (void)[[NSWorkspace sharedWorkspace] openURL:url];
        dispatch_async(dispatch_get_main_queue(), ^{
            slim_thumbnail_hide();
        });
    }
}

- (void)pluginButtonClicked:(NSButton *)sender {
    [self runPluginWithIdentifier:sender.identifier];
}

- (void)runPluginWithIdentifier:(NSString *)identifier {
    SlimPluginManager *manager = [SlimPluginManager sharedManager];
    SlimPlugin *plugin = [manager pluginWithIdentifier:identifier];
    if (plugin == nil) {
        return;
    }
    slim_thumbnail_hide();
    [manager runPlugin:plugin completion:^(BOOL ok, NSString *message) {
        SlimPresentPluginResult(ok, plugin.name, message);
    }];
}

- (void)overflowPressed:(NSButton *)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    for (SlimPlugin *plugin in _plugins) {
        NSMenuItem *item =
            [[NSMenuItem alloc] initWithTitle:plugin.name
                                       action:@selector(overflowSelected:)
                                keyEquivalent:@""];
        item.target = self;
        item.representedObject = plugin.identifier;
        item.image = [NSImage imageWithSystemSymbolName:plugin.iconName
                              accessibilityDescription:plugin.name];
        [menu addItem:item];
    }
    NSPoint location = NSMakePoint(NSMinX(sender.frame),
                                   NSMaxY(sender.frame) + 4.0);
    [menu popUpMenuPositioningItem:nil atLocation:location inView:self];
}

- (void)overflowSelected:(NSMenuItem *)sender {
    [self runPluginWithIdentifier:sender.representedObject];
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

    NSMutableArray<SlimPlugin *> *plugins = [NSMutableArray array];
    for (SlimPlugin *plugin in [[SlimPluginManager sharedManager] plugins]) {
        if (plugin.type == SLIM_PLUGIN_POST_PROCESS) {
            [plugins addObject:plugin];
        }
    }
    NSUInteger visiblePlugins = MIN(plugins.count, (NSUInteger)4);
    CGFloat rowWidth = 8.0 + (CGFloat)visiblePlugins * 34.0;
    if (plugins.count > visiblePlugins) {
        rowWidth += 34.0;
    }
    rowWidth += 8.0;

    CGFloat contentWidth = imageWidth + 12.0;
    if (plugins.count > 0) {
        contentWidth = MAX(contentWidth, rowWidth + 8.0);
    }
    CGFloat contentHeight = imageHeight + 12.0 + ((plugins.count > 0) ? 28.0 : 0.0);
    NSSize contentSize = NSMakeSize(contentWidth, contentHeight);

    NSImage *nsImage = [[NSImage alloc] initWithCGImage:image
                                                   size:NSMakeSize((CGFloat)pixelWidth,
                                                                   (CGFloat)pixelHeight)];
    SlimThumbnailView *view =
        [[SlimThumbnailView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width,
                                                            contentSize.height)
                                           image:nsImage
                                        filePath:filePath
                                         plugins:plugins];

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

    if (plugins.count > 0 && seconds > 0) {
        seconds = MAX(seconds, 8);
    }
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
