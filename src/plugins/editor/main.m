/*
 * Slimshot editor plugin
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 *
 * Minimal rectangle annotation editor. Reads the plugin request on stdin,
 * shows a window, and writes PNG + clipboard data on save.
 */

#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static NSString *EL(NSString *zh, NSString *en) {
    NSString *language = [NSLocale preferredLanguages].firstObject;
    return (language != nil && [language hasPrefix:@"zh"]) ? zh : en;
}

static int Respond(NSDictionary *response) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:response
                                                    options:0
                                                      error:&error];
    if (data == nil) {
        return 1;
    }
    (void)fwrite(data.bytes, 1, data.length, stdout);
    (void)fputc('\n', stdout);
    (void)fflush(stdout);
    return 0;
}

static int Fail(NSString *message) {
    return Respond(@{ @"ok" : @NO,
                      @"message" : (message != nil) ? message : @"Editor failed" });
}

@interface SlimEditorView : NSView
@property (nonatomic, strong) NSImage *image;
@property (nonatomic, strong) NSMutableArray<NSValue *> *rectangles;
- (void)undo;
@end

@implementation SlimEditorView {
    NSPoint _dragStart;
    NSRect _currentRect;
    BOOL _dragging;
}

- (instancetype)initWithFrame:(NSRect)frame image:(NSImage *)image {
    self = [super initWithFrame:frame];
    if (self != nil) {
        _image = image;
        _rectangles = [NSMutableArray array];
    }
    return self;
}

- (NSRect)imageRect {
    NSSize imageSize = self.image.size;
    if (imageSize.width <= 0.0 || imageSize.height <= 0.0) {
        return NSZeroRect;
    }
    NSRect bounds = self.bounds;
    CGFloat scale = MIN(bounds.size.width / imageSize.width,
                        bounds.size.height / imageSize.height);
    CGFloat width = imageSize.width * scale;
    CGFloat height = imageSize.height * scale;
    return NSMakeRect((bounds.size.width - width) / 2.0,
                      (bounds.size.height - height) / 2.0, width, height);
}

- (NSPoint)imagePointForViewPoint:(NSPoint)point {
    NSRect rect = [self imageRect];
    NSSize imageSize = self.image.size;
    if (rect.size.width <= 0.0 || rect.size.height <= 0.0) {
        return NSZeroPoint;
    }
    return NSMakePoint((point.x - rect.origin.x) / rect.size.width * imageSize.width,
                       (point.y - rect.origin.y) / rect.size.height * imageSize.height);
}

- (NSRect)viewRectForImageRect:(NSRect)rect {
    NSRect imageRect = [self imageRect];
    NSSize imageSize = self.image.size;
    if (imageSize.width <= 0.0 || imageSize.height <= 0.0) {
        return NSZeroRect;
    }
    return NSMakeRect(imageRect.origin.x + rect.origin.x / imageSize.width * imageRect.size.width,
                      imageRect.origin.y + rect.origin.y / imageSize.height * imageRect.size.height,
                      rect.size.width / imageSize.width * imageRect.size.width,
                      rect.size.height / imageSize.height * imageRect.size.height);
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithCalibratedWhite:0.12 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    NSRect rect = [self imageRect];
    [self.image drawInRect:rect
                  fromRect:NSZeroRect
                 operation:NSCompositingOperationCopy
                  fraction:1.0
            respectFlipped:YES
                     hints:nil];

    [[NSColor systemRedColor] setStroke];
    for (NSValue *value in self.rectangles) {
        NSRect viewRect = [self viewRectForImageRect:value.rectValue];
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSInsetRect(viewRect, 1.0, 1.0)];
        path.lineWidth = 2.5;
        [path stroke];
    }
    if (_dragging && _currentRect.size.width > 0.0 && _currentRect.size.height > 0.0) {
        NSRect viewRect = [self viewRectForImageRect:_currentRect];
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSInsetRect(viewRect, 1.0, 1.0)];
        path.lineWidth = 2.5;
        [path stroke];
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (!NSPointInRect(point, [self imageRect])) {
        return;
    }
    _dragStart = [self imagePointForViewPoint:point];
    _currentRect = NSMakeRect(_dragStart.x, _dragStart.y, 0.0, 0.0);
    _dragging = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_dragging) {
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect imageRect = [self imageRect];
    point.x = MIN(MAX(point.x, imageRect.origin.x), NSMaxX(imageRect));
    point.y = MIN(MAX(point.y, imageRect.origin.y), NSMaxY(imageRect));
    NSPoint imagePoint = [self imagePointForViewPoint:point];
    _currentRect = NSMakeRect(MIN(_dragStart.x, imagePoint.x),
                              MIN(_dragStart.y, imagePoint.y),
                              fabs(imagePoint.x - _dragStart.x),
                              fabs(imagePoint.y - _dragStart.y));
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    if (!_dragging) {
        return;
    }
    _dragging = NO;
    if (_currentRect.size.width >= 2.0 && _currentRect.size.height >= 2.0) {
        [self.rectangles addObject:[NSValue valueWithRect:_currentRect]];
    }
    _currentRect = NSZeroRect;
    [self setNeedsDisplay:YES];
}

- (void)undo {
    if (self.rectangles.count > 0) {
        [self.rectangles removeLastObject];
        [self setNeedsDisplay:YES];
    }
}

@end

@interface SlimEditorController : NSObject <NSWindowDelegate>
@end

@interface SlimEditorController ()
- (void)save:(id)sender;
@end

@implementation SlimEditorController {
    CGImageRef _image;
    NSImage *_displayImage;
    NSString *_outputDir;
    NSWindow *_window;
    SlimEditorView *_editorView;
    BOOL _finished;
}

- (instancetype)initWithImage:(CGImageRef)image outputDir:(NSString *)outputDir {
    self = [super init];
    if (self != nil) {
        _image = CGImageRetain(image);
        _displayImage = [[NSImage alloc]
            initWithCGImage:image
                       size:NSMakeSize((CGFloat)CGImageGetWidth(image),
                                       (CGFloat)CGImageGetHeight(image))];
        _outputDir = [outputDir copy];
    }
    return self;
}

- (void)dealloc {
    if (_image != NULL) {
        CGImageRelease(_image);
    }
}

- (void)present {
    NSRect contentRect = NSMakeRect(0, 0, 900, 600);
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:contentRect
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = EL(@"Slimshot 编辑", @"Slimshot Editor");
    window.delegate = self;
    [window setReleasedWhenClosed:NO];
    window.minSize = NSMakeSize(560, 400);

    NSView *content = window.contentView;
    CGFloat width = contentRect.size.width;
    CGFloat height = contentRect.size.height;
    const CGFloat toolbarHeight = 44.0;

    NSView *toolbar = [[NSView alloc] initWithFrame:
        NSMakeRect(0, height - toolbarHeight, width, toolbarHeight)];
    toolbar.autoresizingMask = (NSViewWidthSizable | NSViewMinYMargin);
    [content addSubview:toolbar];

    NSButton *undoButton = [NSButton buttonWithTitle:EL(@"撤销", @"Undo")
                                              target:self
                                              action:@selector(undo:)];
    NSButton *saveButton = [NSButton buttonWithTitle:EL(@"保存并复制", @"Save & Copy")
                                              target:self
                                              action:@selector(save:)];
    NSButton *cancelButton = [NSButton buttonWithTitle:EL(@"取消", @"Cancel")
                                                target:self
                                                action:@selector(cancel:)];
    undoButton.bezelStyle = NSBezelStyleRounded;
    saveButton.bezelStyle = NSBezelStyleRounded;
    cancelButton.bezelStyle = NSBezelStyleRounded;
    saveButton.keyEquivalent = @"\r";

    NSStackView *buttons = [NSStackView stackViewWithViews:
        @[ undoButton, saveButton, cancelButton ]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.alignment = NSLayoutAttributeCenterY;
    buttons.spacing = 8.0;
    buttons.frame = NSMakeRect(12, 8, width - 24, 28);
    buttons.autoresizingMask = NSViewWidthSizable;
    [toolbar addSubview:buttons];

    NSTextField *hint = [NSTextField labelWithString:
        EL(@"拖动鼠标绘制红色矩形", @"Drag to draw red rectangles")];
    hint.font = [NSFont systemFontOfSize:11.0];
    hint.textColor = [NSColor secondaryLabelColor];
    hint.frame = NSMakeRect(12, 8, width - 24, 14);
    hint.alignment = NSTextAlignmentRight;
    hint.autoresizingMask = NSViewWidthSizable;
    [toolbar addSubview:hint];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, width, 1)];
    separator.boxType = NSBoxSeparator;
    separator.autoresizingMask = NSViewWidthSizable;
    [toolbar addSubview:separator];

    _editorView = [[SlimEditorView alloc]
        initWithFrame:NSMakeRect(0, 0, width, height - toolbarHeight)
                image:_displayImage];
    _editorView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    [content addSubview:_editorView];

    _window = window;
    [NSApp activateIgnoringOtherApps:YES];
    [window center];
    [window makeKeyAndOrderFront:nil];
}

- (void)finishWithResponse:(NSDictionary *)response {
    if (_finished) {
        return;
    }
    _finished = YES;
    (void)Respond(response);
    [NSApp terminate:nil];
}

- (void)undo:(id)sender {
    (void)sender;
    [_editorView undo];
}

- (void)cancel:(id)sender {
    (void)sender;
    [self finishWithResponse:@{
        @"ok" : @YES,
        @"message" : EL(@"已取消", @"Cancelled"),
        @"output_path" : [NSNull null],
        @"clipboard_text" : @""
    }];
}

- (NSString *)outputPath {
    NSString *dir = (_outputDir.length > 0) ? _outputDir : NSTemporaryDirectory();
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *name = [NSString stringWithFormat:@"Slimshot-edit-%@.png",
                                                [formatter stringFromDate:[NSDate date]]];
    return [dir stringByAppendingPathComponent:name];
}

- (void)save:(id)sender {
    (void)sender;
    size_t width = CGImageGetWidth(_image);
    size_t height = CGImageGetHeight(_image);
    if (width == 0 || height == 0) {
        [self finishWithResponse:@{ @"ok" : @NO, @"message" : @"invalid image size" }];
        return;
    }

    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (space == NULL) {
        space = CGColorSpaceCreateDeviceRGB();
    }
    CGContextRef context = CGBitmapContextCreate(
        NULL, width, height, 8, width * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (context == NULL) {
        [self finishWithResponse:@{ @"ok" : @NO, @"message" : @"could not render image" }];
        return;
    }

    CGContextDrawImage(context, CGRectMake(0, 0, (CGFloat)width, (CGFloat)height), _image);
    CGContextSetRGBStrokeColor(context, 1.0, 0.15, 0.15, 1.0);
    CGFloat lineWidth = MAX(3.0, (CGFloat)width / 400.0);
    CGContextSetLineWidth(context, lineWidth);
    for (NSValue *value in _editorView.rectangles) {
        CGRect rect = value.rectValue;
        CGContextStrokeRect(context, rect);
    }
    CGImageRef edited = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (edited == NULL) {
        [self finishWithResponse:@{ @"ok" : @NO, @"message" : @"could not render image" }];
        return;
    }

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:edited];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSData *tiff = [rep representationUsingType:NSBitmapImageFileTypeTIFF properties:@{}];
    NSString *path = [self outputPath];
    BOOL wrote = (png != nil) && [png writeToFile:path atomically:YES];

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    BOOL copied = NO;
    if (getenv("SLIMSHOT_EDITOR_SKIP_CLIPBOARD") == NULL) {
        [pasteboard clearContents];
        if (png != nil) {
            copied = [pasteboard setData:png forType:NSPasteboardTypePNG] || copied;
        }
        if (tiff != nil) {
            copied = [pasteboard setData:tiff forType:NSPasteboardTypeTIFF] || copied;
        }
    } else {
        copied = YES;
    }
    CGImageRelease(edited);

    NSString *message = (copied ? EL(@"已复制编辑后的图片", @"Edited image copied")
                                : EL(@"无法写入剪贴板", @"Could not write to clipboard"));
    [self finishWithResponse:@{
        @"ok" : copied ? @YES : @NO,
        @"message" : message,
        @"output_path" : (wrote ? path : [NSNull null]),
        @"clipboard_text" : @""
    }];
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    if (!_finished) {
        [self cancel:nil];
    }
}

@end

#ifndef SLIM_EDITOR_NO_MAIN
int main(void) {
    @autoreleasepool {
        NSData *input = [[NSFileHandle fileHandleWithStandardInput]
            readDataToEndOfFile];
        NSError *jsonError = nil;
        id request = [NSJSONSerialization JSONObjectWithData:input
                                                     options:0
                                                       error:&jsonError];
        if (![request isKindOfClass:[NSDictionary class]]) {
            return Fail(@"invalid request JSON");
        }
        id imagePath = ((NSDictionary *)request)[@"image_path"];
        if (![imagePath isKindOfClass:[NSString class]] ||
            [imagePath length] == 0) {
            return Fail(@"missing image_path");
        }
        NSURL *url = [NSURL fileURLWithPath:imagePath];
        CGImageSourceRef source =
            CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        if (source == NULL) {
            return Fail(@"could not open image");
        }
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CFRelease(source);
        if (image == NULL) {
            return Fail(@"could not decode image");
        }

        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        SlimEditorController *controller = [[SlimEditorController alloc]
            initWithImage:image
                outputDir:((NSDictionary *)request)[@"output_dir"]];
        CGImageRelease(image);
        [controller present];
        if (getenv("SLIMSHOT_EDITOR_AUTOSAVE") != NULL) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(0.3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [controller save:nil];
            });
        }
        [NSApp run];
    }
    return 0;
}
#endif /* SLIM_EDITOR_NO_MAIN */
