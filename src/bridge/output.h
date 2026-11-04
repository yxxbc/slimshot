/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_OUTPUT_H
#define SLIM_OUTPUT_H

#import <Cocoa/Cocoa.h>

#include "config.h"

void slim_output_handle(CGImageRef image, const slim_config_t *config, NSScreen *screen,
                        const char *source);
void slim_output_hide_thumbnail(void);

#endif /* SLIM_OUTPUT_H */
