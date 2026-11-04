/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_THUMBNAIL_H
#define SLIM_THUMBNAIL_H

#import <Cocoa/Cocoa.h>

void slim_thumbnail_show(CGImageRef image, NSScreen *screen, NSString *filePath, int seconds);
void slim_thumbnail_hide(void);

#endif /* SLIM_THUMBNAIL_H */
