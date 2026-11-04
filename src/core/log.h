/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_LOG_H
#define SLIM_LOG_H

#include <stdarg.h>

void slim_log_init(void);
void slim_log_close(void);
void slim_log(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

#endif /* SLIM_LOG_H */
