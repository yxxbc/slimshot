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

/*
 * Recursive XY-cut: split on the largest empty vertical band, then the
 * largest empty horizontal band, and finally fall back to top-to-bottom.
 * This keeps two-column UI screenshots from interleaving sidebar and
 * content lines.
 */
static NSArray<VNRecognizedTextObservation *> *SlimOrderObservations(
    NSArray<VNRecognizedTextObservation *> *observations) {
    if (observations.count <= 1) {
        return observations;
    }

    NSArray<VNRecognizedTextObservation *> *byLeft =
        [observations sortedArrayUsingComparator:^NSComparisonResult(
            VNRecognizedTextObservation *a, VNRecognizedTextObservation *b) {
            CGFloat ax = CGRectGetMinX(a.boundingBox);
            CGFloat bx = CGRectGetMinX(b.boundingBox);
            if (ax < bx) {
                return NSOrderedAscending;
            }
            if (ax > bx) {
                return NSOrderedDescending;
            }
            return NSOrderedSame;
        }];

    CGFloat maxRight = -CGFLOAT_MAX;
    CGFloat bestGap = 0.0;
    NSUInteger splitIndex = NSNotFound;
    for (NSUInteger i = 0; i < byLeft.count; i++) {
        CGRect box = byLeft[i].boundingBox;
        if (i > 0) {
            CGFloat gap = CGRectGetMinX(box) - maxRight;
            if (gap > bestGap) {
                bestGap = gap;
                splitIndex = i;
            }
        }
        maxRight = MAX(maxRight, CGRectGetMaxX(box));
    }
    if (splitIndex != NSNotFound && bestGap >= 0.04) {
        NSArray *left = [byLeft subarrayWithRange:NSMakeRange(0, splitIndex)];
        NSArray *right = [byLeft subarrayWithRange:
            NSMakeRange(splitIndex, byLeft.count - splitIndex)];
        NSMutableArray *ordered = [NSMutableArray array];
        [ordered addObjectsFromArray:SlimOrderObservations(left)];
        [ordered addObjectsFromArray:SlimOrderObservations(right)];
        return ordered;
    }

    NSArray<VNRecognizedTextObservation *> *byTop =
        [observations sortedArrayUsingComparator:^NSComparisonResult(
            VNRecognizedTextObservation *a, VNRecognizedTextObservation *b) {
            CGFloat at = CGRectGetMaxY(a.boundingBox);
            CGFloat bt = CGRectGetMaxY(b.boundingBox);
            if (at > bt) {
                return NSOrderedAscending;
            }
            if (at < bt) {
                return NSOrderedDescending;
            }
            return NSOrderedSame;
        }];

    CGFloat minBottom = CGFLOAT_MAX;
    bestGap = 0.0;
    splitIndex = NSNotFound;
    for (NSUInteger i = 0; i < byTop.count; i++) {
        CGRect box = byTop[i].boundingBox;
        if (i > 0) {
            CGFloat gap = minBottom - CGRectGetMaxY(box);
            if (gap > bestGap) {
                bestGap = gap;
                splitIndex = i;
            }
        }
        minBottom = MIN(minBottom, CGRectGetMinY(box));
    }
    if (splitIndex != NSNotFound && bestGap >= 0.012) {
        NSArray *top = [byTop subarrayWithRange:NSMakeRange(0, splitIndex)];
        NSArray *bottom = [byTop subarrayWithRange:
            NSMakeRange(splitIndex, byTop.count - splitIndex)];
        NSMutableArray *ordered = [NSMutableArray array];
        [ordered addObjectsFromArray:SlimOrderObservations(top)];
        [ordered addObjectsFromArray:SlimOrderObservations(bottom)];
        return ordered;
    }

    return [observations sortedArrayUsingComparator:^NSComparisonResult(
        VNRecognizedTextObservation *a, VNRecognizedTextObservation *b) {
        CGRect rectA = a.boundingBox;
        CGRect rectB = b.boundingBox;
        CGFloat topA = CGRectGetMaxY(rectA);
        CGFloat topB = CGRectGetMaxY(rectB);
        if (fabs(topA - topB) > 0.01) {
            return (topA > topB) ? NSOrderedAscending : NSOrderedDescending;
        }
        CGFloat leftA = CGRectGetMinX(rectA);
        CGFloat leftB = CGRectGetMinX(rectB);
        if (fabs(leftA - leftB) < 0.001) {
            return NSOrderedSame;
        }
        return (leftA < leftB) ? NSOrderedAscending : NSOrderedDescending;
    }];
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

        NSArray<VNRecognizedTextObservation *> *sorted =
            SlimOrderObservations(visionRequest.results ?: @[]);

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
