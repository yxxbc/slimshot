/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

#include <math.h>

#include "capture.h"
#include "capture_composite.h"
#include "config.h"
#include "log.h"
#include "output.h"
#include "overlay.h"
#include "screen_geometry.h"
#include "thumbnail.h"

@implementation SlimCaptureController {
    slim_config_t *_config;
    BOOL _busy;
    SlimOverlayController *_overlay;
}

- (instancetype)initWithConfig:(slim_config_t *)config {
    self = [super init];
    if (self != nil) {
        _config = config;
    }
    return self;
}

- (void)captureMode:(SlimCaptureMode)mode {
    [self captureMode:mode onScreen:nil];
}

- (void)captureMode:(SlimCaptureMode)mode onScreen:(NSScreen *)screen {
    if (_busy) {
        slim_log("capture already in progress");
        return;
    }
    _busy = YES;
    slim_output_hide_thumbnail();

    BOOL followCursor = (screen == nil);
    NSScreen *targetScreen = screen;
    if (targetScreen != nil && ![[NSScreen screens] containsObject:targetScreen]) {
        targetScreen = nil;
        followCursor = YES;
    }
    if (targetScreen == nil) {
        targetScreen = [self screenUnderMouse];
        followCursor = YES;
    }
    if (targetScreen == nil) {
        [self failWithMessage:NSLocalizedString(@"capture.error.no_screen", nil)];
        return;
    }

    __weak SlimCaptureController *weakSelf = self;
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO
                                              onScreenWindowsOnly:YES
                                               completionHandler:^(SCShareableContent *content,
                                                                   NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SlimCaptureController *strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            if (content == nil) {
                [strongSelf failWithError:error];
                return;
            }

            if (mode == SlimCaptureModeWindow) {
                [strongSelf presentWindowOverlayForScreen:targetScreen content:content];
                return;
            }

            if (mode == SlimCaptureModeRegion) {
                [strongSelf captureRegionDisplays:content
                                      startScreen:targetScreen
                                      allDisplays:followCursor];
                return;
            }

            SCDisplay *display = [strongSelf displayForScreen:targetScreen inContent:content];
            if (display == nil) {
                [strongSelf failWithMessage:NSLocalizedString(@"capture.error.display_not_found", nil)];
                return;
            }

            [strongSelf captureDisplay:display
                            completion:^(CGImageRef image, NSError *captureError) {
                SlimCaptureController *controller = weakSelf;
                if (controller == nil) {
                    if (image != NULL) {
                        CGImageRelease(image);
                    }
                    return;
                }
                if (image == NULL) {
                    [controller failWithError:captureError];
                    return;
                }
                slim_output_handle(image, controller->_config, targetScreen, "full");
                CGImageRelease(image);
                controller->_busy = NO;
            }];
        });
    }];
}

- (NSScreen *)screenUnderMouse {
    CGEventRef event = CGEventCreate(NULL);
    CGPoint point = CGPointZero;
    if (event != NULL) {
        point = CGEventGetLocation(event);
        CFRelease(event);
    }

    CGDirectDisplayID displayID = kCGNullDirectDisplay;
    uint32_t displayCount = 0;
    CGGetDisplaysWithPoint(point, 1, &displayID, &displayCount);
    if (displayCount > 0) {
        NSScreen *screen = SlimScreenForDisplayID(displayID);
        if (screen != nil) {
            return screen;
        }
        slim_log("screen under mouse: displayID=%u has no NSScreen", displayID);
    }

    NSPoint mouse = [NSEvent mouseLocation];
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSPointInRect(mouse, screen.frame)) {
            return screen;
        }
    }
    slim_log("screen under mouse: falling back to main screen");
    return [NSScreen mainScreen];
}

- (SCDisplay *)displayForScreen:(NSScreen *)screen inContent:(SCShareableContent *)content {
    NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
    CGDirectDisplayID displayID = (CGDirectDisplayID)screenNumber.unsignedIntValue;
    for (SCDisplay *display in content.displays) {
        if (display.displayID == displayID) {
            return display;
        }
    }
    return nil;
}

- (void)captureDisplay:(SCDisplay *)display
            completion:(void (^)(CGImageRef image, NSError *error))completion {
    SCContentFilter *filter =
        [[SCContentFilter alloc] initWithDisplay:display excludingWindows:@[]];
    SCStreamConfiguration *configuration = [[SCStreamConfiguration alloc] init];

    float scale = filter.pointPixelScale;
    if (scale <= 0.0f) {
        scale = 1.0f;
    }
    configuration.width = (size_t)llround((double)display.width * (double)scale);
    configuration.height = (size_t)llround((double)display.height * (double)scale);
    if (configuration.width == 0 || configuration.height == 0) {
        if (completion != nil) {
            NSError *sizeError = [NSError
                errorWithDomain:@"Slimshot"
                           code:1
                       userInfo:@{ NSLocalizedDescriptionKey :
                                       NSLocalizedString(@"capture.error.invalid_display_size", nil) }];
            completion(NULL, sizeError);
        }
        return;
    }

    configuration.showsCursor = _config->include_cursor ? YES : NO;
    configuration.scalesToFit = NO;
    configuration.preservesAspectRatio = YES;
    configuration.captureResolution = SCCaptureResolutionBest;
    configuration.ignoreShadowsDisplay = YES;

    [SCScreenshotManager
        captureImageWithFilter:filter
                 configuration:configuration
             completionHandler:^(CGImageRef image, NSError *error) {
        if (image == NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion != nil) {
                    completion(NULL, error);
                }
            });
            return;
        }

        CGImageRetain(image);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion != nil) {
                completion(image, nil);
            } else {
                CGImageRelease(image);
            }
        });
    }];
}

- (void)captureRegionDisplays:(SCShareableContent *)content
                   startScreen:(NSScreen *)startScreen
                   allDisplays:(BOOL)allDisplays {
    NSArray<SCDisplay *> *displays = nil;
    if (allDisplays) {
        displays = content.displays;
    } else {
        SCDisplay *display = [self displayForScreen:startScreen inContent:content];
        if (display != nil) {
            displays = @[ display ];
        }
    }

    if (displays.count == 0) {
        [self failWithMessage:NSLocalizedString(@"capture.error.no_displays", nil)];
        return;
    }

    NSNumber *startNumber = startScreen.deviceDescription[@"NSScreenNumber"];
    CGDirectDisplayID startDisplayID = (CGDirectDisplayID)startNumber.unsignedIntValue;

    __block NSInteger pending = (NSInteger)displays.count;
    __block BOOL startFound = NO;
    NSMutableArray<SlimScreenCapture *> *captures = [NSMutableArray array];

    for (SCDisplay *display in displays) {
        NSScreen *screen = SlimScreenForSCDisplay(display);
        if (screen == nil) {
            pending--;
            continue;
        }

        [self captureDisplay:display
                  completion:^(CGImageRef image, NSError *error) {
            if (image != NULL) {
                SlimScreenCapture *capture =
                    [[SlimScreenCapture alloc] initWithScreen:screen image:image];
                CGImageRelease(image);
                [captures addObject:capture];
                if (display.displayID == startDisplayID) {
                    startFound = YES;
                }
            } else {
                const char *message = error.localizedDescription.UTF8String;
                slim_log("region display capture failed: %s",
                         message != NULL ? message : "");
            }

            pending--;
            if (pending == 0) {
                if (!startFound || captures.count == 0) {
                    [self failWithMessage:NSLocalizedString(@"capture.error.start_display_failed", nil)];
                    return;
                }
                [self presentRegionOverlayWithCaptures:captures
                                               content:content
                                           startScreen:startScreen];
            }
        }];
    }

    if (pending == 0) {
        [self failWithMessage:NSLocalizedString(@"capture.error.no_displays", nil)];
    }
}

- (void)presentRegionOverlayWithCaptures:(NSArray<SlimScreenCapture *> *)captures
                                 content:(SCShareableContent *)content
                             startScreen:(NSScreen *)startScreen {
    __weak SlimCaptureController *weakSelf = self;
    SlimOverlayController *overlay = [[SlimOverlayController alloc]
        initWithMode:SlimOverlayModeRegion
        screenCaptures:captures
      shareableContent:content
           startScreen:startScreen
              onRegion:^(NSArray<SlimScreenCapture *> *allCaptures, CGRect selectionGlobal) {
                  SlimCaptureController *strongSelf = weakSelf;
                  if (strongSelf != nil) {
                      [strongSelf handleRegionSelection:selectionGlobal
                                               captures:allCaptures
                                                 screen:startScreen];
                  }
              }
              onWindow:^(SCWindow *window) {
                  (void)window;
              }
              onCancel:^{
                  SlimCaptureController *strongSelf = weakSelf;
                  if (strongSelf != nil) {
                      strongSelf->_busy = NO;
                  }
              }];

    if (overlay == nil) {
        [self failWithMessage:NSLocalizedString(@"capture.error.region_overlay_failed", nil)];
        return;
    }
    _overlay = overlay;
    [overlay show];
}

- (void)handleRegionSelection:(CGRect)selection
                     captures:(NSArray<SlimScreenCapture *> *)captures
                       screen:(NSScreen *)screen {
    CGImageRef image = SlimCopyCompositeFromCaptures(captures, selection);
    if (image == NULL) {
        slim_log("region composite failed");
        _busy = NO;
        return;
    }

    slim_config_t *config = _config;
    __weak SlimCaptureController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        slim_output_handle(image, config, screen, "region");
        CGImageRelease(image);
        SlimCaptureController *strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf->_busy = NO;
        }
    });
}

- (void)presentWindowOverlayForScreen:(NSScreen *)screen
                              content:(SCShareableContent *)content {
    slim_log("window overlay: screen=%s", screen.localizedName.UTF8String);
    __weak SlimCaptureController *weakSelf = self;
    SlimOverlayController *overlay = [[SlimOverlayController alloc]
        initWithMode:SlimOverlayModeWindow
        screenCaptures:@[]
      shareableContent:content
           startScreen:screen
              onRegion:^(NSArray<SlimScreenCapture *> *captures, CGRect selectionGlobal) {
                  (void)captures;
                  (void)selectionGlobal;
              }
              onWindow:^(SCWindow *window) {
                  SlimCaptureController *strongSelf = weakSelf;
                  if (strongSelf != nil) {
                      NSScreen *clickedScreen = [strongSelf screenUnderMouse];
                      [strongSelf captureWindow:window
                                         screen:(clickedScreen != nil ? clickedScreen : screen)];
                  }
              }
              onCancel:^{
                  SlimCaptureController *strongSelf = weakSelf;
                  if (strongSelf != nil) {
                      strongSelf->_busy = NO;
                  }
              }];

    if (overlay == nil) {
        [self failWithMessage:NSLocalizedString(@"capture.error.window_overlay_failed", nil)];
        return;
    }
    _overlay = overlay;
    [overlay show];
}

- (void)captureWindow:(SCWindow *)window screen:(NSScreen *)screen {
    NSString *owner = window.owningApplication.applicationName;
    const char *ownerName = owner.UTF8String;
    const char *screenName = screen.localizedName.UTF8String;
    slim_log("window capture: id=%u owner=%s screen=%s frame=%.0fx%.0f",
             (unsigned int)window.windowID,
             ownerName != NULL ? ownerName : "",
             screenName != NULL ? screenName : "",
             window.frame.size.width, window.frame.size.height);

    SCContentFilter *filter =
        [[SCContentFilter alloc] initWithDesktopIndependentWindow:window];
    SCStreamConfiguration *configuration = [[SCStreamConfiguration alloc] init];

    float scale = filter.pointPixelScale;
    if (scale <= 0.0f) {
        scale = (float)screen.backingScaleFactor;
    }
    CGRect contentRect = filter.contentRect;
    if (CGRectIsNull(contentRect) || CGRectIsInfinite(contentRect) ||
        contentRect.size.width < 1.0 || contentRect.size.height < 1.0) {
        contentRect = window.frame;
    }
    if (contentRect.size.width < 1.0 || contentRect.size.height < 1.0) {
        [self failWithMessage:NSLocalizedString(@"capture.error.invalid_window_size", nil)];
        return;
    }

    configuration.width = (size_t)llround((double)contentRect.size.width * (double)scale);
    configuration.height = (size_t)llround((double)contentRect.size.height * (double)scale);
    if (configuration.width == 0 || configuration.height == 0) {
        [self failWithMessage:NSLocalizedString(@"capture.error.invalid_window_size", nil)];
        return;
    }
    configuration.showsCursor = NO;
    configuration.scalesToFit = NO;
    configuration.preservesAspectRatio = YES;
    configuration.captureResolution = SCCaptureResolutionBest;
    configuration.ignoreShadowsSingleWindow = YES;

    CFTimeInterval start = CFAbsoluteTimeGetCurrent();
    __weak SlimCaptureController *weakSelf = self;
    [SCScreenshotManager
        captureImageWithFilter:filter
                 configuration:configuration
             completionHandler:^(CGImageRef image, NSError *error) {
        if (image == NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf failWithError:error];
            });
            return;
        }

        CGImageRetain(image);
        dispatch_async(dispatch_get_main_queue(), ^{
            SlimCaptureController *strongSelf = weakSelf;
            if (strongSelf == nil) {
                CGImageRelease(image);
                return;
            }
            slim_log("window captured in %.1f ms",
                     (CFAbsoluteTimeGetCurrent() - start) * 1000.0);
            slim_output_handle(image, strongSelf->_config, screen, "window");
            CGImageRelease(image);
            strongSelf->_busy = NO;
        });
    }];
}

- (void)failWithError:(NSError *)error {
    NSString *message = error.localizedDescription;
    if (message.length == 0) {
        message = NSLocalizedString(@"capture.error.unknown", nil);
    }
    [self failWithMessage:message];
}

- (void)failWithMessage:(NSString *)message {
    const char *text = message.UTF8String;
    slim_log("capture failed: %s", text != NULL ? text : "");
    _busy = NO;

    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = NSLocalizedString(@"alert.capture_failed.title", nil);
    alert.informativeText = (message != nil) ? message : @"";
    [alert addButtonWithTitle:NSLocalizedString(@"alert.ok", nil)];
    [alert runModal];
}

@end
