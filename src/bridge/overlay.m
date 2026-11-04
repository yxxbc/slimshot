/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

#include <math.h>
#include <unistd.h>

#include "log.h"
#include "overlay.h"

typedef NS_ENUM(NSInteger, SlimDragMode) {
    SlimDragModeNone,
    SlimDragModeNew,
    SlimDragModeMove,
    SlimDragModeLeft,
    SlimDragModeRight,
    SlimDragModeTop,
    SlimDragModeBottom,
    SlimDragModeTopLeft,
    SlimDragModeTopRight,
    SlimDragModeBottomLeft,
    SlimDragModeBottomRight
};

typedef NS_ENUM(NSInteger, SlimOverlayButton) {
    SlimOverlayButtonNone,
    SlimOverlayButtonCapture,
    SlimOverlayButtonCancel
};

@interface SlimWindowInfo : NSObject
@property (nonatomic, strong) SCWindow *window;
@property (nonatomic, assign) CGRect globalRect;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *title;
@end

@implementation SlimWindowInfo
@end

@interface SlimScreenCapture ()
@property (nonatomic, assign) NSRect localRect;
@property (nonatomic, strong) NSImage *nsImage;
@end

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

static BOOL SlimRectIsValid(NSRect rect) {
    return rect.size.width > 0.5 && rect.size.height > 0.5;
}

static NSRect SlimNormalizedRect(NSPoint a, NSPoint b) {
    CGFloat x = MIN(a.x, b.x);
    CGFloat y = MIN(a.y, b.y);
    CGFloat width = fabs(a.x - b.x);
    CGFloat height = fabs(a.y - b.y);
    return NSMakeRect(x, y, width, height);
}

static NSArray<SlimWindowInfo *> *SlimBuildWindowInfos(SCShareableContent *content) {
    NSMutableArray<SlimWindowInfo *> *result = [NSMutableArray array];
    if (content == nil) {
        return result;
    }

    NSMutableDictionary<NSNumber *, SCWindow *> *windowsByID = [NSMutableDictionary dictionary];
    for (SCWindow *window in content.windows) {
        windowsByID[@(window.windowID)] = window;
    }

    CFArrayRef windowList = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    if (windowList == NULL) {
        return result;
    }

    CFIndex count = CFArrayGetCount(windowList);
    for (CFIndex i = 0; i < count; i++) {
        NSDictionary *info =
            (__bridge NSDictionary *)CFArrayGetValueAtIndex(windowList, i);

        NSNumber *layer = info[(__bridge NSString *)kCGWindowLayer];
        if (layer == nil || layer.integerValue != 0) {
            continue;
        }
        NSNumber *pid = info[(__bridge NSString *)kCGWindowOwnerPID];
        if (pid != nil && pid.intValue == getpid()) {
            continue;
        }
        NSNumber *alpha = info[(__bridge NSString *)kCGWindowAlpha];
        if (alpha != nil && alpha.doubleValue < 0.01) {
            continue;
        }
        NSNumber *windowNumber = info[(__bridge NSString *)kCGWindowNumber];
        if (windowNumber == nil) {
            continue;
        }
        SCWindow *scWindow = windowsByID[windowNumber];
        if (scWindow == nil || !scWindow.onScreen || scWindow.windowLayer != 0) {
            continue;
        }

        NSDictionary *boundsDict = info[(__bridge NSString *)kCGWindowBounds];
        if (boundsDict == nil) {
            continue;
        }
        CGRect cgFrame = CGRectZero;
        if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)boundsDict,
                                                    &cgFrame)) {
            continue;
        }
        if (cgFrame.size.width < 2.0 || cgFrame.size.height < 2.0) {
            continue;
        }

        SlimWindowInfo *windowInfo = [[SlimWindowInfo alloc] init];
        windowInfo.window = scWindow;
        windowInfo.globalRect = cgFrame;

        NSString *owner = info[(__bridge NSString *)kCGWindowOwnerName];
        if (owner.length == 0) {
            owner = scWindow.owningApplication.applicationName;
        }
        windowInfo.appName = (owner != nil) ? owner : @"";

        NSString *title = info[(__bridge NSString *)kCGWindowName];
        if (title.length == 0) {
            title = scWindow.title;
        }
        windowInfo.title = (title != nil) ? title : @"";

        [result addObject:windowInfo];
    }
    CFRelease(windowList);
    return result;
}

@interface SlimOverlayWindow : NSWindow
@end

@implementation SlimOverlayWindow
- (BOOL)canBecomeKeyWindow {
    return YES;
}
- (BOOL)canBecomeMainWindow {
    return NO;
}
@end

@class SlimOverlayView;

@protocol SlimOverlayViewDelegate <NSObject>
- (void)overlayView:(SlimOverlayView *)view didSelectRegion:(NSRect)rect;
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
- (NSRect)selectionRect;
- (CGRect)selectionGlobalRect;
- (CGRect)referenceCg;
@end

@implementation SlimOverlayView {
    NSArray<SlimScreenCapture *> *_captures;
    NSArray<SlimWindowInfo *> *_windows;
    SlimOverlayMode _mode;
    __weak id<SlimOverlayViewDelegate> _delegate;
    CGFloat _displayScale;
    NSRect _hintRect;
    CGRect _referenceCg;

    NSRect _selection;
    NSRect _selectionBounds;
    BOOL _showsToolbar;
    BOOL _showsHint;
    SlimWindowInfo *_highlightedWindow;
    SlimWindowInfo *_windowAtMouseDown;
    NSPoint _mousePoint;
    NSPoint _dragStart;
    NSRect _initialSelection;
    SlimDragMode _dragMode;
    BOOL _didDrag;
    NSTrackingArea *_trackingArea;

    NSRect _toolbarRect;
    NSRect _captureButtonRect;
    NSRect _cancelButtonRect;
    SlimOverlayButton _hoveredButton;
}

- (instancetype)initWithFrame:(NSRect)frame
                         mode:(SlimOverlayMode)mode
                     captures:(NSArray<SlimScreenCapture *> *)captures
                      windows:(NSArray<SlimWindowInfo *> *)windows
                     delegate:(id<SlimOverlayViewDelegate>)delegate {
    self = [super initWithFrame:frame];
    if (self != nil) {
        _mode = mode;
        _captures = [captures copy];
        _windows = [windows copy];
        _delegate = delegate;
        _displayScale = 1.0;
        _hintRect = frame;
        _selection = NSZeroRect;
        _selectionBounds = frame;
        _showsToolbar = NO;
        _showsHint = NO;
        _mousePoint = NSMakePoint(NSMidX(frame), NSMidY(frame));
        for (SlimScreenCapture *capture in _captures) {
            capture.localRect = self.bounds;
        }
    }
    return self;
}

- (void)setDisplayScale:(CGFloat)scale {
    _displayScale = (scale > 0.0) ? scale : 1.0;
    [self setNeedsDisplay:YES];
}

- (void)setHintRect:(NSRect)rect {
    _hintRect = rect;
    [self setNeedsDisplay:YES];
}

- (void)setReferenceCg:(CGRect)rect {
    _referenceCg = rect;
    [self setNeedsDisplay:YES];
}

- (void)setSelectionBounds:(NSRect)bounds {
    _selectionBounds = bounds;
}

- (void)setSelectionRect:(NSRect)rect {
    _selection = rect;
    [self setNeedsDisplay:YES];
}

- (void)setShowsToolbar:(BOOL)flag {
    if (_showsToolbar != flag) {
        _showsToolbar = flag;
        [self setNeedsDisplay:YES];
    }
}

- (void)setShowsHint:(BOOL)flag {
    if (_showsHint != flag) {
        _showsHint = flag;
        [self setNeedsDisplay:YES];
    }
}

- (NSRect)selectionRect {
    return _selection;
}

- (CGRect)selectionGlobalRect {
    return CGRectMake(_selection.origin.x + _referenceCg.origin.x,
                      _selection.origin.y + _referenceCg.origin.y,
                      _selection.size.width, _selection.size.height);
}

- (CGRect)referenceCg {
    return _referenceCg;
}

- (void)notifySelectionChanged {
    [_delegate overlayViewDidChangeSelection:self];
}

- (NSRect)localRectForWindowInfo:(SlimWindowInfo *)info {
    CGRect global = info.globalRect;
    return NSMakeRect(global.origin.x - _referenceCg.origin.x,
                      global.origin.y - _referenceCg.origin.y,
                      global.size.width, global.size.height);
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    self.window.acceptsMouseMovedEvents = YES;
    [self.window makeFirstResponder:self];
    [self primeMouseLocation];
    [[NSCursor crosshairCursor] set];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:(NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                      NSTrackingActiveAlways | NSTrackingInVisibleRect)
               owner:self
            userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)primeMouseLocation {
    if (self.window == nil) {
        return;
    }
    NSPoint screenPoint = [NSEvent mouseLocation];
    NSPoint windowPoint = [self.window convertPointFromScreen:screenPoint];
    _mousePoint = [self convertPoint:windowPoint fromView:nil];
    if (_mode == SlimOverlayModeWindow || !SlimRectIsValid(_selection)) {
        _highlightedWindow = [self windowAtPoint:_mousePoint];
    }
    [self setNeedsDisplay:YES];
}

- (SlimWindowInfo *)windowAtPoint:(NSPoint)point {
    NSPoint global = NSMakePoint(point.x + _referenceCg.origin.x,
                                 point.y + _referenceCg.origin.y);
    for (SlimWindowInfo *info in _windows) {
        if (NSPointInRect(global, info.globalRect)) {
            return info;
        }
    }
    return nil;
}

- (void)logWindowHit:(SlimWindowInfo *)info localPoint:(NSPoint)point {
    NSString *owner = info.window.owningApplication.applicationName;
    const char *ownerName = owner.UTF8String;
    CGRect global = info.globalRect;
    slim_log("window hit: local=(%.0f,%.0f) global=(%.0f,%.0f) id=%u owner=%s "
             "rect=(%.0f,%.0f %.0fx%.0f)",
             point.x, point.y,
             point.x + _referenceCg.origin.x,
             point.y + _referenceCg.origin.y,
             (unsigned int)info.window.windowID,
             ownerName != NULL ? ownerName : "",
             global.origin.x, global.origin.y,
             global.size.width, global.size.height);
}

- (SlimDragMode)handleAtPoint:(NSPoint)point {
    if (!SlimRectIsValid(_selection)) {
        return SlimDragModeNone;
    }
    const CGFloat handle = 7.0;
    NSRect rect = _selection;
    BOOL nearLeft = fabs(point.x - NSMinX(rect)) <= handle;
    BOOL nearRight = fabs(point.x - NSMaxX(rect)) <= handle;
    BOOL nearTop = fabs(point.y - NSMinY(rect)) <= handle;
    BOOL nearBottom = fabs(point.y - NSMaxY(rect)) <= handle;
    BOOL withinX = point.x >= NSMinX(rect) - handle && point.x <= NSMaxX(rect) + handle;
    BOOL withinY = point.y >= NSMinY(rect) - handle && point.y <= NSMaxY(rect) + handle;
    if (!withinX || !withinY) {
        return SlimDragModeNone;
    }
    if (nearLeft && nearTop) {
        return SlimDragModeTopLeft;
    }
    if (nearRight && nearTop) {
        return SlimDragModeTopRight;
    }
    if (nearLeft && nearBottom) {
        return SlimDragModeBottomLeft;
    }
    if (nearRight && nearBottom) {
        return SlimDragModeBottomRight;
    }
    if (nearLeft) {
        return SlimDragModeLeft;
    }
    if (nearRight) {
        return SlimDragModeRight;
    }
    if (nearTop) {
        return SlimDragModeTop;
    }
    if (nearBottom) {
        return SlimDragModeBottom;
    }
    return SlimDragModeNone;
}

- (NSRect)resizedRect:(NSRect)rect
                 mode:(SlimDragMode)mode
                point:(NSPoint)point
               bounds:(NSRect)bounds {
    CGFloat minX = NSMinX(rect);
    CGFloat maxX = NSMaxX(rect);
    CGFloat minY = NSMinY(rect);
    CGFloat maxY = NSMaxY(rect);
    CGFloat boundMinX = NSMinX(bounds);
    CGFloat boundMaxX = NSMaxX(bounds);
    CGFloat boundMinY = NSMinY(bounds);
    CGFloat boundMaxY = NSMaxY(bounds);

    switch (mode) {
        case SlimDragModeLeft:
            minX = MIN(MAX(point.x, boundMinX), maxX - 1.0);
            break;
        case SlimDragModeRight:
            maxX = MAX(MIN(point.x, boundMaxX), minX + 1.0);
            break;
        case SlimDragModeTop:
            minY = MIN(MAX(point.y, boundMinY), maxY - 1.0);
            break;
        case SlimDragModeBottom:
            maxY = MAX(MIN(point.y, boundMaxY), minY + 1.0);
            break;
        case SlimDragModeTopLeft:
            minX = MIN(MAX(point.x, boundMinX), maxX - 1.0);
            minY = MIN(MAX(point.y, boundMinY), maxY - 1.0);
            break;
        case SlimDragModeTopRight:
            maxX = MAX(MIN(point.x, boundMaxX), minX + 1.0);
            minY = MIN(MAX(point.y, boundMinY), maxY - 1.0);
            break;
        case SlimDragModeBottomLeft:
            minX = MIN(MAX(point.x, boundMinX), maxX - 1.0);
            maxY = MAX(MIN(point.y, boundMaxY), minY + 1.0);
            break;
        case SlimDragModeBottomRight:
            maxX = MAX(MIN(point.x, boundMaxX), minX + 1.0);
            maxY = MAX(MIN(point.y, boundMaxY), minY + 1.0);
            break;
        default:
            break;
    }
    return NSMakeRect(minX, minY, maxX - minX, maxY - minY);
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    _mousePoint = point;
    [self.window makeKeyWindow];

    if (_mode == SlimOverlayModeWindow) {
        SlimWindowInfo *info = [self windowAtPoint:point];
        if (info != nil) {
            [self logWindowHit:info localPoint:point];
            [_delegate overlayView:self didSelectWindow:info.window];
        }
        return;
    }

    if (event.clickCount == 2 && SlimRectIsValid(_selection) &&
        NSPointInRect(point, _selection)) {
        [self finishRegion];
        return;
    }

    [self updateToolbarLayout];
    if (SlimRectIsValid(_toolbarRect)) {
        if (NSPointInRect(point, _captureButtonRect)) {
            [self finishRegion];
            return;
        }
        if (NSPointInRect(point, _cancelButtonRect)) {
            [_delegate overlayViewDidCancel:self];
            return;
        }
        if (NSPointInRect(point, _toolbarRect)) {
            return;
        }
    }

    SlimDragMode handle = [self handleAtPoint:point];
    if (handle != SlimDragModeNone) {
        _dragMode = handle;
        _dragStart = point;
        _initialSelection = _selection;
        _didDrag = NO;
        return;
    }

    if (SlimRectIsValid(_selection) && NSPointInRect(point, _selection)) {
        _dragMode = SlimDragModeMove;
        _dragStart = point;
        _initialSelection = _selection;
        _didDrag = NO;
        return;
    }

    _dragMode = SlimDragModeNew;
    _dragStart = point;
    _selection = NSZeroRect;
    _windowAtMouseDown = [self windowAtPoint:point];
    _highlightedWindow = _windowAtMouseDown;
    if (_windowAtMouseDown != nil) {
        [self logWindowHit:_windowAtMouseDown localPoint:point];
    }
    _didDrag = NO;
    [self notifySelectionChanged];
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    _mousePoint = point;
    _hoveredButton = SlimOverlayButtonNone;

    CGFloat dx = point.x - _dragStart.x;
    CGFloat dy = point.y - _dragStart.y;
    if (fabs(dx) > 2.0 || fabs(dy) > 2.0) {
        _didDrag = YES;
    }

    NSRect bounds = _selectionBounds;
    switch (_dragMode) {
        case SlimDragModeNew: {
            NSRect rect = SlimNormalizedRect(_dragStart, point);
            _selection = NSIntersectionRect(rect, bounds);
            break;
        }
        case SlimDragModeMove: {
            NSRect rect = _initialSelection;
            rect.origin.x += dx;
            rect.origin.y += dy;
            if (NSMinX(rect) < NSMinX(bounds)) {
                rect.origin.x = NSMinX(bounds);
            }
            if (NSMinY(rect) < NSMinY(bounds)) {
                rect.origin.y = NSMinY(bounds);
            }
            if (NSMaxX(rect) > NSMaxX(bounds)) {
                rect.origin.x = NSMaxX(bounds) - rect.size.width;
            }
            if (NSMaxY(rect) > NSMaxY(bounds)) {
                rect.origin.y = NSMaxY(bounds) - rect.size.height;
            }
            _selection = rect;
            break;
        }
        default:
            _selection = [self resizedRect:_initialSelection
                                      mode:_dragMode
                                     point:point
                                    bounds:bounds];
            break;
    }
    [self notifySelectionChanged];
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    if (_mode == SlimOverlayModeWindow) {
        _dragMode = SlimDragModeNone;
        return;
    }

    if (_dragMode == SlimDragModeNew && !_didDrag) {
        if (_windowAtMouseDown != nil) {
            _selection = [self localRectForWindowInfo:_windowAtMouseDown];
            [self notifySelectionChanged];
            [self setNeedsDisplay:YES];
            [self finishRegion];
            return;
        }
        _selection = NSZeroRect;
        [self notifySelectionChanged];
    }

    _dragMode = SlimDragModeNone;
    _windowAtMouseDown = nil;
    [self setNeedsDisplay:YES];
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    _mousePoint = point;
    if (_mode == SlimOverlayModeWindow || !SlimRectIsValid(_selection)) {
        _highlightedWindow = [self windowAtPoint:point];
    }

    SlimOverlayButton hovered = [self buttonAtPoint:point];
    if (hovered != _hoveredButton) {
        _hoveredButton = hovered;
    }

    if (hovered != SlimOverlayButtonNone) {
        [[NSCursor pointingHandCursor] set];
    } else if (SlimRectIsValid(_toolbarRect) && NSPointInRect(point, _toolbarRect)) {
        [[NSCursor arrowCursor] set];
    } else {
        [[self cursorForPoint:point] set];
    }
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    if (_hoveredButton != SlimOverlayButtonNone) {
        _hoveredButton = SlimOverlayButtonNone;
        [self setNeedsDisplay:YES];
    }
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 53) {
        [_delegate overlayViewDidCancel:self];
        return;
    }
    if (event.keyCode == 36 || event.keyCode == 76) {
        if (_mode == SlimOverlayModeWindow) {
            if (_highlightedWindow != nil) {
                [_delegate overlayView:self didSelectWindow:_highlightedWindow.window];
            }
        } else {
            if (!SlimRectIsValid(_selection) && _highlightedWindow != nil) {
                _selection = [self localRectForWindowInfo:_highlightedWindow];
                [self notifySelectionChanged];
            }
            [self finishRegion];
        }
        return;
    }
    [super keyDown:event];
}

- (void)cancelOperation:(id)sender {
    (void)sender;
    [_delegate overlayViewDidCancel:self];
}

- (void)rightMouseDown:(NSEvent *)event {
    (void)event;
    [_delegate overlayViewDidCancel:self];
}

- (void)finishRegion {
    NSRect rect = NSIntersectionRect(_selection, _selectionBounds);
    if (!SlimRectIsValid(rect)) {
        return;
    }
    [_delegate overlayView:self didSelectRegion:rect];
}

- (NSCursor *)cursorForPoint:(NSPoint)point {
    if (_mode == SlimOverlayModeWindow) {
        return [NSCursor crosshairCursor];
    }

    [self updateToolbarLayout];
    if (NSPointInRect(point, _captureButtonRect) ||
        NSPointInRect(point, _cancelButtonRect)) {
        return [NSCursor pointingHandCursor];
    }
    if (SlimRectIsValid(_toolbarRect) && NSPointInRect(point, _toolbarRect)) {
        return [NSCursor arrowCursor];
    }

    if (SlimRectIsValid(_selection)) {
        SlimDragMode handle = [self handleAtPoint:point];
        if (handle != SlimDragModeNone) {
            return [self cursorForDragMode:handle];
        }
        if (NSPointInRect(point, _selection)) {
            return [NSCursor openHandCursor];
        }
    }
    return [NSCursor crosshairCursor];
}

- (NSCursor *)cursorForDragMode:(SlimDragMode)mode {
    if (@available(macOS 15.0, *)) {
        NSCursorFrameResizePosition position =
            NSCursorFrameResizePositionTop;
        switch (mode) {
            case SlimDragModeLeft:
                position = NSCursorFrameResizePositionLeft;
                break;
            case SlimDragModeRight:
                position = NSCursorFrameResizePositionRight;
                break;
            case SlimDragModeTop:
                position = NSCursorFrameResizePositionTop;
                break;
            case SlimDragModeBottom:
                position = NSCursorFrameResizePositionBottom;
                break;
            case SlimDragModeTopLeft:
                position = (NSCursorFrameResizePositionTop |
                            NSCursorFrameResizePositionLeft);
                break;
            case SlimDragModeTopRight:
                position = (NSCursorFrameResizePositionTop |
                            NSCursorFrameResizePositionRight);
                break;
            case SlimDragModeBottomLeft:
                position = (NSCursorFrameResizePositionBottom |
                            NSCursorFrameResizePositionLeft);
                break;
            case SlimDragModeBottomRight:
                position = (NSCursorFrameResizePositionBottom |
                            NSCursorFrameResizePositionRight);
                break;
            default:
                break;
        }
        return [NSCursor frameResizeCursorFromPosition:position
                                           inDirections:NSCursorFrameResizeDirectionsAll];
    }

    switch (mode) {
        case SlimDragModeLeft:
        case SlimDragModeRight:
            return [NSCursor resizeLeftRightCursor];
        case SlimDragModeTop:
        case SlimDragModeBottom:
            return [NSCursor resizeUpDownCursor];
        default:
            return [NSCursor crosshairCursor];
    }
}

- (NSSize)imagePixelScale {
    CGFloat scale = (_displayScale > 0.0) ? _displayScale : 1.0;
    return NSMakeSize(scale, scale);
}

- (NSDictionary *)labelAttributes {
    return @{
        NSFontAttributeName : [NSFont monospacedSystemFontOfSize:12.0
                                                          weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : [NSColor whiteColor]
    };
}

- (NSDictionary *)buttonAttributes {
    return @{
        NSFontAttributeName : [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : [NSColor whiteColor]
    };
}

- (NSString *)selectionText {
    NSSize scale = [self imagePixelScale];
    int pixelWidth = (int)llround(_selection.size.width * scale.width);
    int pixelHeight = (int)llround(_selection.size.height * scale.height);
    NSString *text = [NSString stringWithFormat:@"%.0f × %.0f  (%.0f, %.0f)",
                                               _selection.size.width,
                                               _selection.size.height,
                                               _selection.origin.x,
                                               _selection.origin.y];
    if (fabs(scale.width - 1.0) > 0.01 || fabs(scale.height - 1.0) > 0.01) {
        text = [text stringByAppendingFormat:@"  %d × %d px", pixelWidth, pixelHeight];
    }
    return text;
}

- (void)updateToolbarLayout {
    _toolbarRect = NSZeroRect;
    _captureButtonRect = NSZeroRect;
    _cancelButtonRect = NSZeroRect;
    if (!_showsToolbar || _mode != SlimOverlayModeRegion ||
        !SlimRectIsValid(_selection)) {
        return;
    }

    NSDictionary *labelAttrs = [self labelAttributes];
    NSDictionary *buttonAttrs = [self buttonAttributes];
    NSString *sizeText = [self selectionText];
    NSString *captureTitle = NSLocalizedString(@"overlay.capture", nil);
    NSString *cancelTitle = NSLocalizedString(@"overlay.cancel", nil);

    NSSize sizeTextSize = [sizeText sizeWithAttributes:labelAttrs];
    NSSize captureTextSize = [captureTitle sizeWithAttributes:buttonAttrs];
    NSSize cancelTextSize = [cancelTitle sizeWithAttributes:buttonAttrs];

    CGFloat padding = 9.0;
    CGFloat gap = 8.0;
    CGFloat buttonHeight = 26.0;
    CGFloat barHeight = buttonHeight + 12.0;
    CGFloat captureWidth = MAX(70.0, captureTextSize.width + 18.0);
    CGFloat cancelWidth = MAX(54.0, cancelTextSize.width + 18.0);
    CGFloat barWidth = padding + sizeTextSize.width + gap + captureWidth + gap +
                       cancelWidth + padding;

    NSRect bounds = self.bounds;
    CGFloat x = NSMinX(_selection);
    CGFloat y = NSMaxY(_selection) + 8.0;
    if (y + barHeight > bounds.size.height - 8.0) {
        y = NSMinY(_selection) - barHeight - 8.0;
    }
    y = MIN(MAX(y, 8.0), MAX(8.0, bounds.size.height - barHeight - 8.0));
    x = MIN(MAX(x, 8.0), MAX(8.0, bounds.size.width - barWidth - 8.0));

    _toolbarRect = NSMakeRect(x, y, barWidth, barHeight);
    CGFloat buttonY = y + (barHeight - buttonHeight) / 2.0;
    CGFloat buttonsX = x + padding + sizeTextSize.width + gap;
    _captureButtonRect = NSMakeRect(buttonsX, buttonY, captureWidth, buttonHeight);
    _cancelButtonRect = NSMakeRect(NSMaxX(_captureButtonRect) + gap, buttonY,
                                   cancelWidth, buttonHeight);
}

- (SlimOverlayButton)buttonAtPoint:(NSPoint)point {
    [self updateToolbarLayout];
    if (NSPointInRect(point, _captureButtonRect)) {
        return SlimOverlayButtonCapture;
    }
    if (NSPointInRect(point, _cancelButtonRect)) {
        return SlimOverlayButtonCancel;
    }
    return SlimOverlayButtonNone;
}

- (void)drawButtonInRect:(NSRect)rect
                   title:(NSString *)title
                 hovered:(BOOL)hovered
                 primary:(BOOL)primary
              attributes:(NSDictionary *)attributes {
    NSColor *background = primary ? [NSColor systemBlueColor]
                                  : [NSColor colorWithCalibratedWhite:0.38 alpha:1.0];
    [background setFill];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect
                                                          xRadius:6.0
                                                          yRadius:6.0];
    [path fill];

    if (hovered) {
        [[NSColor whiteColor] setStroke];
        path.lineWidth = 1.5;
        [path stroke];
    }

    NSSize textSize = [title sizeWithAttributes:attributes];
    NSPoint point = NSMakePoint(NSMidX(rect) - textSize.width / 2.0,
                                NSMidY(rect) - textSize.height / 2.0);
    [title drawAtPoint:point withAttributes:attributes];
}

- (void)drawToolbar {
    if (!_showsToolbar || _mode != SlimOverlayModeRegion ||
        !SlimRectIsValid(_selection)) {
        return;
    }
    [self updateToolbarLayout];
    if (!SlimRectIsValid(_toolbarRect)) {
        return;
    }

    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.82] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:_toolbarRect
                                     xRadius:8.0
                                     yRadius:8.0] fill];

    NSDictionary *labelAttrs = [self labelAttributes];
    NSString *sizeText = [self selectionText];
    NSSize sizeTextSize = [sizeText sizeWithAttributes:labelAttrs];
    CGFloat textY = NSMinY(_toolbarRect) +
                    (NSHeight(_toolbarRect) - sizeTextSize.height) / 2.0;
    [sizeText drawAtPoint:NSMakePoint(NSMinX(_toolbarRect) + 9.0, textY)
           withAttributes:labelAttrs];

    NSDictionary *buttonAttrs = [self buttonAttributes];
    [self drawButtonInRect:_captureButtonRect
                     title:NSLocalizedString(@"overlay.capture", nil)
                   hovered:(_hoveredButton == SlimOverlayButtonCapture)
                   primary:YES
                attributes:buttonAttrs];
    [self drawButtonInRect:_cancelButtonRect
                     title:NSLocalizedString(@"overlay.cancel", nil)
                   hovered:(_hoveredButton == SlimOverlayButtonCancel)
                   primary:NO
                attributes:buttonAttrs];
}

- (void)drawLabel:(NSString *)text atPoint:(NSPoint)point {
    if (text.length == 0) {
        return;
    }
    if (text.length > 90) {
        text = [[text substringToIndex:87] stringByAppendingString:@"…"];
    }
    NSDictionary *attributes = [self labelAttributes];
    NSSize textSize = [text sizeWithAttributes:attributes];
    NSSize labelSize = NSMakeSize(textSize.width + 12.0, textSize.height + 8.0);
    NSRect bounds = self.bounds;
    CGFloat maxX = MAX(8.0, bounds.size.width - labelSize.width - 8.0);
    CGFloat maxY = MAX(8.0, bounds.size.height - labelSize.height - 8.0);
    CGFloat x = MIN(MAX(point.x, 8.0), maxX);
    CGFloat y = MIN(MAX(point.y, 8.0), maxY);

    NSRect background = NSMakeRect(x, y, labelSize.width, labelSize.height);
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.78] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:background xRadius:5.0 yRadius:5.0] fill];
    [text drawAtPoint:NSMakePoint(x + 6.0, y + 4.0) withAttributes:attributes];
}

- (void)drawHint {
    if (!_showsHint) {
        return;
    }
    if (_mode == SlimOverlayModeRegion && SlimRectIsValid(_selection)) {
        return;
    }
    NSString *key = (_mode == SlimOverlayModeRegion) ? @"overlay.hint.region"
                                                     : @"overlay.hint.window";
    NSString *hint = NSLocalizedString(key, nil);
    NSDictionary *attributes = [self labelAttributes];
    NSSize textSize = [hint sizeWithAttributes:attributes];
    NSSize labelSize = NSMakeSize(textSize.width + 12.0, textSize.height + 8.0);
    NSRect area = SlimRectIsValid(_hintRect) ? _hintRect : self.bounds;
    CGFloat x = area.origin.x + (area.size.width - labelSize.width) / 2.0;
    CGFloat y = area.origin.y + 12.0;
    [self drawLabel:hint atPoint:NSMakePoint(x, y)];
}

- (void)drawHandlesForRect:(NSRect)rect {
    if (rect.size.width < 16.0 || rect.size.height < 16.0) {
        return;
    }
    CGFloat size = 6.0;
    NSPoint points[8] = {
        NSMakePoint(NSMinX(rect), NSMinY(rect)),
        NSMakePoint(NSMidX(rect), NSMinY(rect)),
        NSMakePoint(NSMaxX(rect), NSMinY(rect)),
        NSMakePoint(NSMinX(rect), NSMidY(rect)),
        NSMakePoint(NSMaxX(rect), NSMidY(rect)),
        NSMakePoint(NSMinX(rect), NSMaxY(rect)),
        NSMakePoint(NSMidX(rect), NSMaxY(rect)),
        NSMakePoint(NSMaxX(rect), NSMaxY(rect)),
    };
    for (int i = 0; i < 8; i++) {
        NSRect handle = NSMakeRect(points[i].x - size / 2.0,
                                   points[i].y - size / 2.0, size, size);
        [[NSColor whiteColor] setFill];
        NSRectFill(handle);
        [[NSColor systemBlueColor] setStroke];
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:handle];
        path.lineWidth = 1.0;
        [path stroke];
    }
}

- (void)drawCaptures {
    for (SlimScreenCapture *capture in _captures) {
        if (capture.nsImage != nil && SlimRectIsValid(capture.localRect)) {
            [capture.nsImage drawInRect:capture.localRect
                               fromRect:NSZeroRect
                              operation:NSCompositingOperationCopy
                               fraction:1.0
                         respectFlipped:YES
                                  hints:nil];
        }
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = self.bounds;

    [self drawCaptures];

    CGFloat dimAlpha = (_mode == SlimOverlayModeRegion) ? 0.45 : 0.35;
    [[NSColor colorWithCalibratedWhite:0.0 alpha:dimAlpha] setFill];
    NSRectFill(bounds);

    if (_mode == SlimOverlayModeRegion) {
        if (SlimRectIsValid(_selection) && _captures.count > 0) {
            NSRect clearRect = NSIntersectionRect(_selection, bounds);
            if (SlimRectIsValid(clearRect)) {
                [NSGraphicsContext saveGraphicsState];
                NSRectClip(clearRect);
                [self drawCaptures];
                [NSGraphicsContext restoreGraphicsState];
            }
        }
    } else if (_highlightedWindow != nil) {
        NSRect clearRect = NSIntersectionRect([self localRectForWindowInfo:_highlightedWindow], bounds);
        if (SlimRectIsValid(clearRect)) {
            CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
            CGContextSaveGState(context);
            CGContextSetBlendMode(context, kCGBlendModeClear);
            CGContextFillRect(context, clearRect);
            CGContextRestoreGState(context);
        }
    }

    BOOL selectionValid = SlimRectIsValid(_selection);
    if (_highlightedWindow != nil &&
        (_mode == SlimOverlayModeWindow || !selectionValid)) {
        NSRect rect = NSIntersectionRect([self localRectForWindowInfo:_highlightedWindow], bounds);
        if (SlimRectIsValid(rect)) {
            [[NSColor systemBlueColor] setStroke];
            NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSInsetRect(rect, 1.0, 1.0)];
            path.lineWidth = 2.0;
            [path stroke];
        }
    }

    if (selectionValid) {
        NSRect rect = _selection;
        [[NSColor whiteColor] setStroke];
        NSBezierPath *outer = [NSBezierPath bezierPathWithRect:NSInsetRect(rect, 0.5, 0.5)];
        outer.lineWidth = 1.0;
        [outer stroke];

        [[NSColor systemBlueColor] setStroke];
        NSBezierPath *inner = [NSBezierPath bezierPathWithRect:NSInsetRect(rect, 1.5, 1.5)];
        inner.lineWidth = 1.0;
        [inner stroke];
        [self drawHandlesForRect:rect];
    }

    if (!selectionValid || _dragMode == SlimDragModeNew) {
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.65] setStroke];
        NSBezierPath *vertical = [NSBezierPath bezierPath];
        [vertical moveToPoint:NSMakePoint(_mousePoint.x, 0.0)];
        [vertical lineToPoint:NSMakePoint(_mousePoint.x, bounds.size.height)];
        vertical.lineWidth = 1.0;
        [vertical stroke];

        NSBezierPath *horizontal = [NSBezierPath bezierPath];
        [horizontal moveToPoint:NSMakePoint(0.0, _mousePoint.y)];
        [horizontal lineToPoint:NSMakePoint(bounds.size.width, _mousePoint.y)];
        horizontal.lineWidth = 1.0;
        [horizontal stroke];
    }

    if (!selectionValid && _highlightedWindow != nil) {
        NSString *name = _highlightedWindow.appName;
        if (name.length == 0) {
            name = _highlightedWindow.title;
        }
        NSRect rect = [self localRectForWindowInfo:_highlightedWindow];
        NSString *text = [NSString stringWithFormat:@"%@  %.0f × %.0f", name,
                                                   rect.size.width, rect.size.height];
        [self drawLabel:text atPoint:NSMakePoint(_mousePoint.x + 16.0, _mousePoint.y + 16.0)];
    }

    [self drawToolbar];
    [self drawHint];
}

@end

@interface SlimOverlayController () <SlimOverlayViewDelegate>
@end

static CGRect SlimScreenGlobalCGRect(NSScreen *screen, CGFloat mainHeight) {
    NSRect frame = screen.frame;
    return CGRectMake(frame.origin.x,
                      mainHeight - (frame.origin.y + frame.size.height),
                      frame.size.width, frame.size.height);
}

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
    CGFloat mainHeight = (allScreens.count > 0)
                             ? allScreens.firstObject.frame.size.height
                             : targetScreen.frame.size.height;

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
