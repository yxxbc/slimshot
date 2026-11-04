/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#include "log.h"
#include "paths.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static FILE *g_log;
static int g_inited;
static int g_atexit_registered;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

void slim_log_init(void) {
    pthread_mutex_lock(&g_lock);
    if (g_inited) {
        pthread_mutex_unlock(&g_lock);
        return;
    }
    g_inited = 1;

    char path[SLIM_PATH_MAX];
    if (slim_paths_log(path, sizeof path) == 0) {
        (void)slim_mkdir_parent(path, 0755);

        struct stat st;
        if (stat(path, &st) == 0 && st.st_size > 1024 * 1024) {
            char old_path[SLIM_PATH_MAX];
            int n = snprintf(old_path, sizeof old_path, "%s.1", path);
            if (n > 0 && (size_t)n < sizeof old_path) {
                (void)unlink(old_path);
                (void)rename(path, old_path);
            }
        }

        g_log = fopen(path, "a");
        if (g_log != NULL) {
            (void)setvbuf(g_log, NULL, _IOLBF, 0);
        }
    }

    if (!g_atexit_registered) {
        (void)atexit(slim_log_close);
        g_atexit_registered = 1;
    }
    pthread_mutex_unlock(&g_lock);
}

void slim_log_close(void) {
    pthread_mutex_lock(&g_lock);
    if (g_log != NULL) {
        (void)fclose(g_log);
        g_log = NULL;
    }
    g_inited = 0;
    pthread_mutex_unlock(&g_lock);
}

void slim_log(const char *fmt, ...) {
    if (fmt == NULL) {
        return;
    }
    if (!g_inited) {
        slim_log_init();
    }

    char when[32];
    time_t now = time(NULL);
    struct tm tm_now;
    (void)localtime_r(&now, &tm_now);
    (void)strftime(when, sizeof when, "%Y-%m-%d %H:%M:%S", &tm_now);

    va_list ap;
    va_list ap_copy;
    va_start(ap, fmt);
    va_copy(ap_copy, ap);

    pthread_mutex_lock(&g_lock);
    if (g_log != NULL) {
        (void)fprintf(g_log, "[%s] ", when);
        (void)vfprintf(g_log, fmt, ap);
        (void)fputc('\n', g_log);
        (void)fflush(g_log);
    }
    (void)fprintf(stderr, "[%s] ", when);
    (void)vfprintf(stderr, fmt, ap_copy);
    (void)fputc('\n', stderr);
    pthread_mutex_unlock(&g_lock);

    va_end(ap_copy);
    va_end(ap);
}
