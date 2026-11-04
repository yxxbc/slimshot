/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_PATHS_H
#define SLIM_PATHS_H

#include <stddef.h>

#define SLIM_PATH_MAX 1024

int slim_paths_home(char *buf, size_t len);
int slim_paths_app_support(char *buf, size_t len);
int slim_paths_config(char *buf, size_t len);
int slim_paths_log(char *buf, size_t len);
int slim_paths_expand_tilde(const char *in, char *out, size_t len);
int slim_mkdir_p(const char *path, int mode);
int slim_mkdir_parent(const char *path, int mode);

#endif /* SLIM_PATHS_H */
