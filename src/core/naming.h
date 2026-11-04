/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_NAMING_H
#define SLIM_NAMING_H

#include <stddef.h>
#include <time.h>

#include "config.h"

int slim_naming_format(const char *template_str, const struct tm *tm,
                       const char *extension, char *out, size_t len);
int slim_naming_make(const slim_config_t *cfg, const char *extension,
                     char *out, size_t len);
const char *slim_format_extension(const char *format);
int slim_naming_unique(const char *path, char *out, size_t len);

#endif /* SLIM_NAMING_H */
