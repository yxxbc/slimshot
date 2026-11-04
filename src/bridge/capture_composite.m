/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

#include <math.h>

#import "capture_composite.h"
#import "screen_geometry.h"

static CGImageRef SlimCopyCropFromCapture(SlimScreenCapture *capture,
                                          CGRect intersection,
                                          CGRect screenCg) {
    CGImageRef image = capture.image;
    if (image == NULL || screenCg.size.width <= 0.0 || screenCg.size.height <= 0.0) {
        return NULL;
    }

    CGFloat scaleX = (CGFloat)CGImageGetWidth(image) / screenCg.size.width;
    CGFloat scaleY = (CGFloat)CGImageGetHeight(image) / screenCg.size.height;

    CGFloat x = round((intersection.origin.x - screenCg.origin.x) * scaleX);
    CGFloat y = round((intersection.origin.y - screenCg.origin.y) * scaleY);
    CGFloat width = round(intersection.size.width * scaleX);
    CGFloat height = round(intersection.size.height * scaleY);
    if (width < 1.0) {
        width = 1.0;
    }
    if (height < 1.0) {
        height = 1.0;
    }

    CGRect imageBounds = CGRectMake(0, 0, (CGFloat)CGImageGetWidth(image),
                                    (CGFloat)CGImageGetHeight(image));
    CGRect pixelRect = CGRectIntersection(CGRectMake(x, y, width, height), imageBounds);
    if (CGRectIsNull(pixelRect) || pixelRect.size.width < 1.0 ||
        pixelRect.size.height < 1.0) {
        return NULL;
    }
    return CGImageCreateWithImageInRect(image, pixelRect);
}

CGImageRef SlimCopyCompositeFromCaptures(NSArray<SlimScreenCapture *> *captures,
                                         CGRect selection) {
    if (captures.count == 0 || selection.size.width < 1.0 ||
        selection.size.height < 1.0) {
        return NULL;
    }

    CGFloat mainHeight = SlimMainScreenHeight();
    if (mainHeight <= 0.0) {
        mainHeight = selection.size.height;
    }

    NSMutableArray<SlimScreenCapture *> *hits = [NSMutableArray array];
    NSMutableArray<NSValue *> *intersections = [NSMutableArray array];
    CGFloat targetScale = 1.0;

    for (SlimScreenCapture *capture in captures) {
        NSScreen *screen = capture.screen;
        if (screen == nil) {
            continue;
        }
        CGRect screenCg = SlimScreenGlobalCGRect(screen, mainHeight);
        CGRect intersection = CGRectIntersection(selection, screenCg);
        if (CGRectIsNull(intersection) || intersection.size.width < 1.0 ||
            intersection.size.height < 1.0) {
            continue;
        }

        [hits addObject:capture];
        [intersections addObject:[NSValue valueWithRect:intersection]];

        CGFloat scaleX = (CGFloat)CGImageGetWidth(capture.image) / screenCg.size.width;
        CGFloat scaleY = (CGFloat)CGImageGetHeight(capture.image) / screenCg.size.height;
        targetScale = MAX(targetScale, MAX(scaleX, scaleY));
    }

    if (hits.count == 0) {
        return NULL;
    }

    if (hits.count == 1) {
        SlimScreenCapture *capture = hits.firstObject;
        CGRect screenCg = SlimScreenGlobalCGRect(capture.screen, mainHeight);
        CGRect intersection = [intersections.firstObject rectValue];
        return SlimCopyCropFromCapture(capture, intersection, screenCg);
    }

    size_t outputWidth = (size_t)llround(selection.size.width * targetScale);
    size_t outputHeight = (size_t)llround(selection.size.height * targetScale);
    if (outputWidth == 0 || outputHeight == 0) {
        return NULL;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    if (colorSpace == NULL) {
        colorSpace = CGColorSpaceCreateDeviceRGB();
    }
    CGContextRef context = CGBitmapContextCreate(
        NULL, outputWidth, outputHeight, 8, outputWidth * 4, colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) {
        return NULL;
    }

    CGContextSetRGBFillColor(context, 0.0, 0.0, 0.0, 1.0);
    CGContextFillRect(context, CGRectMake(0, 0, outputWidth, outputHeight));

    for (NSUInteger i = 0; i < hits.count; i++) {
        SlimScreenCapture *capture = hits[i];
        CGRect intersection = [intersections[i] rectValue];
        CGRect screenCg = SlimScreenGlobalCGRect(capture.screen, mainHeight);
        CGImageRef crop = SlimCopyCropFromCapture(capture, intersection, screenCg);
        if (crop == NULL) {
            continue;
        }

        CGFloat dx = (intersection.origin.x - selection.origin.x) * targetScale;
        CGFloat dy = (intersection.origin.y - selection.origin.y) * targetScale;
        CGFloat width = intersection.size.width * targetScale;
        CGFloat height = intersection.size.height * targetScale;
        CGRect destination = CGRectMake(dx, (CGFloat)outputHeight - dy - height,
                                        width, height);
        CGContextDrawImage(context, destination, crop);
        CGImageRelease(crop);
    }

    CGImageRef output = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return output;
}
