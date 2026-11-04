/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>

#include <errno.h>
#include <stdio.h>
#include <string.h>

#include "config.h"
#include "log.h"
#include "naming.h"
#include "output.h"
#include "paths.h"
#include "plugins.h"
#include "thumbnail.h"

static CFStringRef SlimUTIForFormat(const char *format) {
    if (strcmp(format, "jpeg") == 0) {
        return CFSTR("public.jpeg");
    }
    if (strcmp(format, "heic") == 0) {
        return CFSTR("public.heic");
    }
    if (strcmp(format, "tiff") == 0) {
        return CFSTR("public.tiff");
    }
    return CFSTR("public.png");
}

static void SlimSetError(NSString **errorMessage, NSString *message) {
    if (errorMessage != NULL) {
        *errorMessage = message;
    }
}

static NSString *SlimSaveImage(CGImageRef image, const slim_config_t *config,
                               NSString **errorMessage) {
    char directory[SLIM_PATH_MAX];
    if (slim_paths_expand_tilde(config->save_directory, directory, sizeof directory) != 0) {
        SlimSetError(errorMessage, NSLocalizedString(@"output.error.save_directory", nil));
        return nil;
    }
    if (slim_mkdir_p(directory, 0755) != 0) {
        SlimSetError(errorMessage,
                     [NSString stringWithFormat:NSLocalizedString(@"output.error.create_directory", nil),
                                                directory, strerror(errno)]);
        return nil;
    }

    char name[SLIM_TEMPLATE_MAX + 64];
    if (slim_naming_make(config, NULL, name, sizeof name) != 0) {
        SlimSetError(errorMessage, NSLocalizedString(@"output.error.filename", nil));
        return nil;
    }

    char path[SLIM_PATH_MAX * 2];
    int n = snprintf(path, sizeof path, "%s/%s", directory, name);
    if (n < 0 || (size_t)n >= sizeof path) {
        SlimSetError(errorMessage, NSLocalizedString(@"output.error.path_too_long", nil));
        return nil;
    }

    char uniquePath[SLIM_PATH_MAX * 2];
    if (slim_naming_unique(path, uniquePath, sizeof uniquePath) != 0) {
        SlimSetError(errorMessage, NSLocalizedString(@"output.error.unique_filename", nil));
        return nil;
    }
    if (slim_mkdir_parent(uniquePath, 0755) != 0) {
        SlimSetError(errorMessage,
                     [NSString stringWithFormat:NSLocalizedString(@"output.error.create_output_directory", nil),
                                                strerror(errno)]);
        return nil;
    }

    NSString *filePath = [NSString stringWithUTF8String:uniquePath];
    if (filePath == nil) {
        SlimSetError(errorMessage, NSLocalizedString(@"output.error.invalid_path", nil));
        return nil;
    }

    NSURL *url = [NSURL fileURLWithPath:filePath];
    CGImageDestinationRef destination =
        CGImageDestinationCreateWithURL((__bridge CFURLRef)url,
                                        SlimUTIForFormat(config->format), 1, NULL);
    if (destination == NULL) {
        SlimSetError(errorMessage, NSLocalizedString(@"output.error.imageio_destination", nil));
        return nil;
    }

    int quality = 0;
    if (strcmp(config->format, "jpeg") == 0) {
        quality = config->jpeg_quality;
    } else if (strcmp(config->format, "heic") == 0) {
        quality = config->heic_quality;
    }

    NSDictionary *properties = nil;
    if (quality > 0) {
        properties = @{
            (__bridge NSString *)kCGImageDestinationLossyCompressionQuality :
                @((double)quality / 100.0)
        };
    }

    CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)properties);
    BOOL ok = CGImageDestinationFinalize(destination);
    CFRelease(destination);

    if (!ok) {
        SlimSetError(errorMessage, NSLocalizedString(@"output.error.encode", nil));
        return nil;
    }
    return filePath;
}

static BOOL SlimCopyToPasteboard(CGImageRef image) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    if (rep == nil) {
        return NO;
    }

    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSData *tiff = [rep representationUsingType:NSBitmapImageFileTypeTIFF properties:@{}];

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];

    BOOL ok = NO;
    if (png != nil) {
        ok = [pasteboard setData:png forType:NSPasteboardTypePNG] || ok;
    }
    if (tiff != nil) {
        ok = [pasteboard setData:tiff forType:NSPasteboardTypeTIFF] || ok;
    }
    return ok;
}

static void SlimShowError(NSString *title, NSString *message) {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = title;
    alert.informativeText = (message != nil) ? message : @"";
    [alert addButtonWithTitle:NSLocalizedString(@"alert.ok", nil)];
    [alert runModal];
}

static NSString *SlimWritePluginCapture(CGImageRef image) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    if (rep == nil) {
        return nil;
    }
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG
                                    properties:@{}];
    if (png == nil) {
        return nil;
    }

    NSString *temporary = NSTemporaryDirectory();
    if (temporary.length == 0) {
        temporary = @"/tmp";
    }
    NSString *directory = [temporary stringByAppendingPathComponent:@"Slimshot"];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL]) {
        return nil;
    }
    NSString *path = [directory stringByAppendingPathComponent:@"last-capture.png"];
    if (![png writeToFile:path atomically:YES]) {
        return nil;
    }
    return path;
}

void slim_output_handle(CGImageRef image, const slim_config_t *config, NSScreen *screen,
                        const char *source) {
    if (image == NULL || config == NULL) {
        return;
    }
    const char *src = (source != NULL) ? source : "capture";

    NSString *savedPath = nil;
    if (config->auto_save) {
        NSString *errorMessage = nil;
        savedPath = SlimSaveImage(image, config, &errorMessage);
        if (savedPath != nil) {
            slim_log("saved %s capture to %s", src, savedPath.UTF8String);
        } else {
            const char *message = errorMessage.UTF8String;
            slim_log("save %s capture failed: %s", src, message != NULL ? message : "");
            SlimShowError(NSLocalizedString(@"alert.output_failed.title", nil), errorMessage);
        }
    }

    if (config->copy_to_clipboard) {
        if (SlimCopyToPasteboard(image)) {
            slim_log("copied %s capture to clipboard", src);
        } else {
            slim_log("copy %s capture to clipboard failed", src);
        }
    }

    NSString *pluginPath = savedPath;
    if (pluginPath == nil &&
        [[SlimPluginManager sharedManager] hasPostProcessPlugins]) {
        pluginPath = SlimWritePluginCapture(image);
        if (pluginPath != nil) {
            slim_log("plugin capture: %s", pluginPath.UTF8String);
        }
    }
    if (pluginPath != nil) {
        double scale = (screen != nil) ? screen.backingScaleFactor : 1.0;
        [[SlimPluginManager sharedManager]
            noteCaptureWithPath:pluginPath
                          width:(int)CGImageGetWidth(image)
                         height:(int)CGImageGetHeight(image)
                          scale:scale
                         source:[NSString stringWithUTF8String:src]];
    }

    if (config->show_thumbnail) {
        slim_thumbnail_show(image, screen, savedPath, config->thumbnail_seconds);
    }
}

void slim_output_hide_thumbnail(void) {
    slim_thumbnail_hide();
}
