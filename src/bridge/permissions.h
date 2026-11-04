/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_PERMISSIONS_H
#define SLIM_PERMISSIONS_H

#include <stdbool.h>

bool slim_screen_capture_authorized(void);
bool slim_request_screen_capture(void);
void slim_open_screen_capture_settings(void);

#endif /* SLIM_PERMISSIONS_H */
