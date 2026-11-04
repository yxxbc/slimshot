/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

#include <unistd.h>

#include "log.h"
#import "overlay_internal.h"
#import "screen_geometry.h"

@interface SlimOverlayController () <SlimOverlayViewDelegate>
@end

@implementation SlimOverlayController {
    NSArray<SlimOverlayWindow *> *_overlayWindows;
    NSArray<SlimOverlayView *> *_overlayViews;
    SlimOverlayWindow *_startWindow;
    SlimOverlayView *_startView;
    NSRunningApplication *_previousApp;
    NSArray<SlimScreenCapture *> *_captures;
    void (^_onRegion)(NSArray<SlimScreenCapture *> *captures, CGRect selectionGlobal);
    void (^_onWindow)(SCWindow *window);
    void (^_onCancel)(void);
    BOOL _finished;
}

- (instancetype)initWithMode:(SlimOverlayMode)mode
              screenCaptures:(NSArray<SlimScreenCapture *> *)captures
            shareableContent:(SCShareableContent *)content
                 startScreen:(NSScreen *)startScreen
                    onRegion:(void (^)(NSArray<SlimScreenCapture *> *captures,
                                       CGRect selectionGlobal))onRegion
                    onWindow:(void (^)(SCWindow *window))onWindow
                    onCancel:(void (^)(void))onCancel {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    NSScreen *targetScreen = (startScreen != nil) ? startScreen : [NSScreen mainScreen];
    if (targetScreen == nil) {
        return nil;
    }

    _onRegion = [onRegion copy];
    _onWindow = [onWindow copy];
    _onCancel = [onCancel copy];
    _captures = [captures copy];

    NSArray<NSScreen *> *allScreens = [NSScreen screens];
    CGFloat mainHeight = SlimMainScreenHeight();
    if (mainHeight <= 0.0) {
        mainHeight = targetScreen.frame.size.height;
    }

    NSMutableArray<NSScreen *> *screensForOverlay = [NSMutableArray array];
    if (mode == SlimOverlayModeRegion) {
        for (SlimScreenCapture *capture in _captures) {
            NSScreen *screen = capture.screen;
            if (screen != nil && ![screensForOverlay containsObject:screen]) {
                [screensForOverlay addObject:screen];
            }
        }
    } else {
        for (NSScreen *screen in allScreens) {
            [screensForOverlay addObject:screen];
        }
    }
    if (screensForOverlay.count == 0) {
        return nil;
    }

    CGRect globalBounds = CGRectZero;
    BOOL firstRect = YES;
    for (NSScreen *screen in screensForOverlay) {
        CGRect rect = SlimScreenGlobalCGRect(screen, mainHeight);
        globalBounds = firstRect ? rect : CGRectUnion(globalBounds, rect);
        firstRect = NO;
    }

    NSArray<SlimWindowInfo *> *windows = SlimBuildWindowInfos(content);
    NSMutableArray<SlimOverlayWindow *> *overlayWindows = [NSMutableArray array];
    NSMutableArray<SlimOverlayView *> *overlayViews = [NSMutableArray array];

    for (NSScreen *screen in screensForOverlay) {
        SlimScreenCapture *viewCapture = nil;
        if (mode == SlimOverlayModeRegion) {
            for (SlimScreenCapture *capture in _captures) {
                if (capture.screen == screen) {
                    viewCapture = capture;
                    break;
                }
            }
        }
        NSArray<SlimScreenCapture *> *viewCaptures =
            (viewCapture != nil) ? @[ viewCapture ] : @[];

        NSRect screenFrame = screen.frame;
        SlimOverlayView *view = [[SlimOverlayView alloc]
            initWithFrame:NSMakeRect(0, 0, screenFrame.size.width, screenFrame.size.height)
                     mode:mode
                 captures:viewCaptures
                  windows:windows
                 delegate:self];

        CGRect screenCg = SlimScreenGlobalCGRect(screen, mainHeight);
        [view setReferenceCg:screenCg];
        NSRect localBounds = NSMakeRect(globalBounds.origin.x - screenCg.origin.x,
                                        globalBounds.origin.y - screenCg.origin.y,
                                        globalBounds.size.width, globalBounds.size.height);
        [view setSelectionBounds:localBounds];
        [view setDisplayScale:screen.backingScaleFactor];
        [view setHintRect:view.bounds];
        [view setShowsHint:(screen == targetScreen)];
        [view setShowsToolbar:NO];

        SlimOverlayWindow *window =
            [[SlimOverlayWindow alloc] initWithContentRect:screenFrame
                                                 styleMask:NSWindowStyleMaskBorderless
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
        window.level = NSScreenSaverWindowLevel;
        window.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                                     NSWindowCollectionBehaviorStationary |
                                     NSWindowCollectionBehaviorFullScreenAuxiliary |
                                     NSWindowCollectionBehaviorIgnoresCycle);
        window.opaque = NO;
        window.backgroundColor = [NSColor clearColor];
        window.hasShadow = NO;
        window.releasedWhenClosed = NO;
        window.acceptsMouseMovedEvents = YES;
        window.ignoresMouseEvents = NO;
        window.contentView = view;

        [overlayWindows addObject:window];
        [overlayViews addObject:view];

        if (screen == targetScreen) {
            _startWindow = window;
            _startView = view;
        }
    }

    _overlayWindows = [overlayWindows copy];
    _overlayViews = [overlayViews copy];

    if (_startWindow == nil) {
        _startWindow = _overlayWindows.firstObject;
        _startView = _overlayViews.firstObject;
        [_startView setShowsHint:YES];
    }
    if (_startWindow == nil) {
        return nil;
    }

    _previousApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
    return self;
}

- (void)dealloc {
    for (SlimOverlayWindow *window in _overlayWindows) {
        [window orderOut:nil];
    }
}

- (void)show {
    [NSApp activateIgnoringOtherApps:YES];
    for (SlimOverlayWindow *window in _overlayWindows) {
        [window orderFront:nil];
    }
    [_startWindow makeKeyAndOrderFront:nil];
    [_startWindow makeFirstResponder:_startView];

    for (NSUInteger i = 0; i < _overlayWindows.count; i++) {
        NSWindow *window = _overlayWindows[i];
        SlimOverlayView *view = _overlayViews[i];
        NSRect frame = window.frame;
        NSRect bounds = view.bounds;
        CGRect ref = [view referenceCg];
        slim_log("overlay screen %lu: window=(%.0f,%.0f %.0fx%.0f) "
                 "view=(%.0f,%.0f %.0fx%.0f) reference=(%.0f,%.0f %.0fx%.0f)",
                 (unsigned long)i,
                 frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
                 bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height,
                 ref.origin.x, ref.origin.y, ref.size.width, ref.size.height);
    }
}

- (void)cancel {
    if (_finished) {
        return;
    }
    _finished = YES;
    void (^cancelBlock)(void) = _onCancel;
    _onRegion = nil;
    _onWindow = nil;
    _onCancel = nil;
    [self closeOverlay];
    if (cancelBlock != nil) {
        cancelBlock();
    }
}

- (void)closeOverlay {
    for (SlimOverlayWindow *window in _overlayWindows) {
        [window orderOut:nil];
        [window close];
    }
    _overlayWindows = nil;
    _overlayViews = nil;
    _startWindow = nil;
    _startView = nil;

    if (_previousApp != nil && _previousApp.processIdentifier != getpid()) {
        (void)[_previousApp activateWithOptions:0];
    }
    _previousApp = nil;
}

- (void)overlayViewDidChangeSelection:(SlimOverlayView *)view {
    (void)view;
    if (_finished) {
        return;
    }

    CGRect global = [view selectionGlobalRect];
    for (SlimOverlayView *other in _overlayViews) {
        CGRect ref = [other referenceCg];
        NSRect local = NSMakeRect(global.origin.x - ref.origin.x,
                                  global.origin.y - ref.origin.y,
                                  global.size.width, global.size.height);
        [other setSelectionRect:local];
    }

    SlimOverlayView *host = nil;
    if (!CGRectIsEmpty(global)) {
        for (SlimOverlayView *candidate in _overlayViews) {
            if (CGRectContainsPoint([candidate referenceCg], global.origin)) {
                host = candidate;
                break;
            }
        }
        if (host == nil) {
            CGFloat bestArea = 0.0;
            for (SlimOverlayView *candidate in _overlayViews) {
                CGRect intersection = CGRectIntersection(global, [candidate referenceCg]);
                if (!CGRectIsNull(intersection)) {
                    CGFloat area = intersection.size.width * intersection.size.height;
                    if (area > bestArea) {
                        bestArea = area;
                        host = candidate;
                    }
                }
            }
        }
    }

    for (SlimOverlayView *candidate in _overlayViews) {
        [candidate setShowsToolbar:(candidate == host)];
        [candidate setNeedsDisplay:YES];
    }
}

- (void)overlayView:(SlimOverlayView *)view didSelectRegion:(NSRect)rect {
    if (_finished) {
        return;
    }
    _finished = YES;

    CGRect ref = [view referenceCg];
    CGRect selectionGlobal = CGRectMake(rect.origin.x + ref.origin.x,
                                        rect.origin.y + ref.origin.y,
                                        rect.size.width, rect.size.height);

    void (^regionBlock)(NSArray<SlimScreenCapture *> *, CGRect) = _onRegion;
    _onRegion = nil;
    _onWindow = nil;
    _onCancel = nil;
    if (regionBlock != nil) {
        regionBlock(_captures, selectionGlobal);
    }
    [self closeOverlay];
}

- (void)overlayView:(SlimOverlayView *)view didSelectWindow:(SCWindow *)window {
    (void)view;
    if (_finished) {
        return;
    }
    _finished = YES;
    void (^windowBlock)(SCWindow *) = _onWindow;
    _onRegion = nil;
    _onWindow = nil;
    _onCancel = nil;
    if (windowBlock != nil) {
        windowBlock(window);
    }
    [self closeOverlay];
}

- (void)overlayViewDidCancel:(SlimOverlayView *)view {
    (void)view;
    if (_finished) {
        return;
    }
    _finished = YES;
    void (^cancelBlock)(void) = _onCancel;
    _onRegion = nil;
    _onWindow = nil;
    _onCancel = nil;
    [self closeOverlay];
    if (cancelBlock != nil) {
        cancelBlock();
    }
}

@end
