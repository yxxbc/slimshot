/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_CONFIG_H
#define SLIM_CONFIG_H

#include <stddef.h>

#include "paths.h"

#define SLIM_FORMAT_MAX 16
#define SLIM_HOTKEY_MAX 64
#define SLIM_LANG_MAX 16
#define SLIM_TEMPLATE_MAX 256

typedef struct {
    int version;
    int copy_to_clipboard;
    int auto_save;
    int include_cursor;
    int show_thumbnail;
    int thumbnail_seconds;
    int launch_at_login;
    char save_directory[SLIM_PATH_MAX];
    char filename_template[SLIM_TEMPLATE_MAX];
    char format[SLIM_FORMAT_MAX];
    int jpeg_quality;
    int heic_quality;
    char language[SLIM_LANG_MAX];
    char hotkey_fullscreen[SLIM_HOTKEY_MAX];
    char hotkey_window[SLIM_HOTKEY_MAX];
    char hotkey_region[SLIM_HOTKEY_MAX];
} slim_config_t;

void slim_config_defaults(slim_config_t *cfg);
int slim_config_load(slim_config_t *cfg, char *err, size_t errlen);
int slim_config_save(const slim_config_t *cfg, char *err, size_t errlen);
int slim_config_load_from_path(slim_config_t *cfg, const char *path, char *err, size_t errlen);
int slim_config_save_to_path(const slim_config_t *cfg, const char *path, char *err, size_t errlen);
int slim_config_path(char *buf, size_t len);

#endif /* SLIM_CONFIG_H */
