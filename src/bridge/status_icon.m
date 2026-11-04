/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import "status_icon.h"

NSImage *SlimStatusIconCreate(void) {
    const CGFloat size = 18.0;
    NSImage *image = [NSImage imageWithSize:NSMakeSize(size, size)
                                    flipped:NO
                             drawingHandler:^BOOL(NSRect rect) {
        (void)rect;
        [[NSColor blackColor] setStroke];

        const CGFloat inset = 2.4;
        const CGFloat arm = 4.6;
        NSBezierPath *frame = [NSBezierPath bezierPath];
        frame.lineWidth = 1.6;
        frame.lineCapStyle = NSLineCapStyleRound;

        [frame moveToPoint:NSMakePoint(inset, inset + arm)];
        [frame lineToPoint:NSMakePoint(inset, inset)];
        [frame lineToPoint:NSMakePoint(inset + arm, inset)];

        [frame moveToPoint:NSMakePoint(size - inset - arm, inset)];
        [frame lineToPoint:NSMakePoint(size - inset, inset)];
        [frame lineToPoint:NSMakePoint(size - inset, inset + arm)];

        [frame moveToPoint:NSMakePoint(inset, size - inset - arm)];
        [frame lineToPoint:NSMakePoint(inset, size - inset)];
        [frame lineToPoint:NSMakePoint(inset + arm, size - inset)];

        [frame moveToPoint:NSMakePoint(size - inset - arm, size - inset)];
        [frame lineToPoint:NSMakePoint(size - inset, size - inset)];
        [frame lineToPoint:NSMakePoint(size - inset, size - inset - arm)];
        [frame stroke];

        NSRect lensRect = NSMakeRect(6.4, 6.4, 5.2, 5.2);
        NSBezierPath *lens = [NSBezierPath bezierPathWithOvalInRect:lensRect];
        lens.lineWidth = 1.5;
        [lens stroke];

        [[NSColor blackColor] setFill];
        NSRectFill(NSMakeRect(8.35, 8.35, 1.3, 1.3));
        return YES;
    }];
    image.template = YES;
    return image;
}
