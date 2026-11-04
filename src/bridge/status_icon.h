/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_STATUS_ICON_H
#define SLIM_STATUS_ICON_H

#import <Cocoa/Cocoa.h>

/* Template image for the menu bar; the system tints it for light/dark bars. */
NSImage *SlimStatusIconCreate(void);

#endif /* SLIM_STATUS_ICON_H */
