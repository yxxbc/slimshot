/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_PERMISSIONS_H
#define SLIM_PERMISSIONS_H

#include <stdbool.h>

typedef enum {
    SLIM_PERMISSION_UNKNOWN = 0, /* never asked; no TCC row for this bundle yet */
    SLIM_PERMISSION_DENIED,
    SLIM_PERMISSION_GRANTED,
} slim_permission_state_t;

/* CGPreflightScreenCaptureAccess only answers yes/no. We remember whether we
 * ever sent a request so the UI can tell "not asked yet" from "explicitly
 * denied", which is the difference between showing the system prompt and
 * sending the user to System Settings. */
slim_permission_state_t slim_screen_capture_state(void);
bool slim_screen_capture_authorized(void);
bool slim_screen_capture_prompted(void);

/* Ask macOS for Screen Recording access. This both shows the system consent
 * dialog (once per login session) and adds Slimshot to the System Settings
 * list. Call it only when the app can come to the foreground. Returns the
 * resulting grant state. */
bool slim_screen_capture_request_frontmost(void);

void slim_open_screen_capture_settings(void);

#endif /* SLIM_PERMISSIONS_H */
