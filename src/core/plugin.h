/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#ifndef SLIM_PLUGIN_H
#define SLIM_PLUGIN_H

#include <stddef.h>

#include "paths.h"

#define SLIM_PLUGIN_ID_MAX 64
#define SLIM_PLUGIN_NAME_MAX 128
#define SLIM_PLUGIN_VERSION_MAX 32

typedef enum {
    SLIM_PLUGIN_POST_PROCESS = 0,
    SLIM_PLUGIN_STANDALONE = 1
} slim_plugin_type_t;

typedef struct {
    char id[SLIM_PLUGIN_ID_MAX];
    char name[SLIM_PLUGIN_NAME_MAX];
    char version[SLIM_PLUGIN_VERSION_MAX];
    slim_plugin_type_t type;
    char directory[SLIM_PATH_MAX];
    char exec_path[SLIM_PATH_MAX * 2];
    int timeout_ms;
    int builtin;
} slim_plugin_t;

typedef struct {
    slim_plugin_t *items;
    size_t count;
} slim_plugin_list_t;

void slim_plugins_init(slim_plugin_list_t *list);
void slim_plugins_free(slim_plugin_list_t *list);

/* Scan builtin_dir and user_dir for <id>/manifest.json. Missing dirs are fine. */
int slim_plugins_discover(slim_plugin_list_t *list,
                          const char *builtin_dir,
                          const char *user_dir,
                          char *err, size_t errlen);

const char *slim_plugin_type_name(slim_plugin_type_t type);

/*
 * Run plugin with request_json on stdin. Returns 0 when the process exits 0.
 * stdout_text/stderr_text are allocated strings owned by the caller and are
 * filled when data was produced, including some failure paths.
 */
int slim_plugin_run(const slim_plugin_t *plugin,
                    const char *request_json,
                    char **stdout_text,
                    char **stderr_text,
                    char *err, size_t errlen);

#endif /* SLIM_PLUGIN_H */
