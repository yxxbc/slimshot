/*
 * Slimshot OCR plugin
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 *
 * Reads the plugin request JSON from stdin, recognizes text with Vision,
 * and writes a single-line response JSON to stdout.
 */

#import <Foundation/Foundation.h>
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

#include <math.h>
#include <stdio.h>

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
                      @"message" : (message != nil) ? message : @"OCR failed" });
}

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

        VNRecognizeTextRequest *visionRequest =
            [[VNRecognizeTextRequest alloc] init];
        visionRequest.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        visionRequest.usesLanguageCorrection = YES;
        visionRequest.recognitionLanguages = @[ @"zh-Hans", @"en-US" ];

        VNImageRequestHandler *handler =
            [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
        NSError *visionError = nil;
        BOOL performed = [handler performRequests:@[ visionRequest ]
                                            error:&visionError];
        CGImageRelease(image);
        if (!performed) {
            return Fail(visionError.localizedDescription ?: @"OCR failed");
        }

        NSArray<VNRecognizedTextObservation *> *observations =
            visionRequest.results ?: @[];
        NSArray<VNRecognizedTextObservation *> *sorted =
            [observations sortedArrayUsingComparator:^NSComparisonResult(
                VNRecognizedTextObservation *a, VNRecognizedTextObservation *b) {
                CGRect rectA = a.boundingBox;
                CGRect rectB = b.boundingBox;
                CGFloat topA = CGRectGetMaxY(rectA);
                CGFloat topB = CGRectGetMaxY(rectB);
                if (fabs(topA - topB) > 0.02) {
                    return (topA > topB) ? NSOrderedAscending : NSOrderedDescending;
                }
                CGFloat leftA = CGRectGetMinX(rectA);
                CGFloat leftB = CGRectGetMinX(rectB);
                if (fabs(leftA - leftB) < 0.001) {
                    return NSOrderedSame;
                }
                return (leftA < leftB) ? NSOrderedAscending : NSOrderedDescending;
            }];

        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (VNRecognizedTextObservation *observation in sorted) {
            VNRecognizedText *text =
                [[observation topCandidates:1] firstObject];
            if (text.string.length > 0) {
                [lines addObject:text.string];
            }
        }

        NSString *result = [lines componentsJoinedByString:@"\n"];
        NSString *message = [NSString stringWithFormat:@"recognized %lu chars",
                                                       (unsigned long)result.length];
        return Respond(@{
            @"ok" : @YES,
            @"message" : message,
            @"output_path" : [NSNull null],
            @"clipboard_text" : result
        });
    }
}
