/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#include "paths.h"

#include <errno.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static int home_dir(char *buf, size_t len) {
    const char *home = getenv("HOME");
    if (home == NULL || home[0] == '\0') {
        struct passwd *pw = getpwuid(getuid());
        home = (pw != NULL) ? pw->pw_dir : NULL;
    }
    if (home == NULL || home[0] == '\0') {
        return -1;
    }
    int n = snprintf(buf, len, "%s", home);
    return (n < 0 || (size_t)n >= len) ? -1 : 0;
}

static int join_path(char *buf, size_t len, const char *a, const char *b) {
    int n = snprintf(buf, len, "%s/%s", a, b);
    return (n < 0 || (size_t)n >= len) ? -1 : 0;
}

int slim_paths_home(char *buf, size_t len) {
    return home_dir(buf, len);
}

int slim_paths_app_support(char *buf, size_t len) {
    char home[SLIM_PATH_MAX];
    if (home_dir(home, sizeof home) != 0) {
        return -1;
    }
    return join_path(buf, len, home, "Library/Application Support/Slimshot");
}

int slim_paths_config(char *buf, size_t len) {
    char dir[SLIM_PATH_MAX];
    if (slim_paths_app_support(dir, sizeof dir) != 0) {
        return -1;
    }
    return join_path(buf, len, dir, "config.json");
}

int slim_paths_log(char *buf, size_t len) {
    char home[SLIM_PATH_MAX];
    if (home_dir(home, sizeof home) != 0) {
        return -1;
    }
    return join_path(buf, len, home, "Library/Logs/Slimshot.log");
}

int slim_paths_expand_tilde(const char *in, char *out, size_t len) {
    if (in == NULL || out == NULL) {
        return -1;
    }
    if (in[0] == '~' && (in[1] == '/' || in[1] == '\0')) {
        char home[SLIM_PATH_MAX];
        if (home_dir(home, sizeof home) != 0) {
            return -1;
        }
        int n = snprintf(out, len, "%s%s", home, in + 1);
        return (n < 0 || (size_t)n >= len) ? -1 : 0;
    }
    int n = snprintf(out, len, "%s", in);
    return (n < 0 || (size_t)n >= len) ? -1 : 0;
}

int slim_mkdir_p(const char *path, int mode) {
    if (path == NULL || path[0] == '\0') {
        return -1;
    }

    char tmp[SLIM_PATH_MAX];
    int n = snprintf(tmp, sizeof tmp, "%s", path);
    if (n < 0 || (size_t)n >= sizeof tmp) {
        return -1;
    }

    size_t len = strlen(tmp);
    while (len > 1 && tmp[len - 1] == '/') {
        tmp[--len] = '\0';
    }

    for (char *p = tmp + 1; *p != '\0'; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, (mode_t)mode) != 0 && errno != EEXIST) {
                return -1;
            }
            *p = '/';
        }
    }
    if (mkdir(tmp, (mode_t)mode) != 0 && errno != EEXIST) {
        return -1;
    }
    return 0;
}

int slim_mkdir_parent(const char *path, int mode) {
    if (path == NULL) {
        return -1;
    }
    char tmp[SLIM_PATH_MAX];
    int n = snprintf(tmp, sizeof tmp, "%s", path);
    if (n < 0 || (size_t)n >= sizeof tmp) {
        return -1;
    }
    char *slash = strrchr(tmp, '/');
    if (slash == NULL || slash == tmp) {
        return 0;
    }
    *slash = '\0';
    return slim_mkdir_p(tmp, mode);
}
