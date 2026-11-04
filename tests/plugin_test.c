/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#include "plugin.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static int g_failures;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #condition); \
            g_failures++;                                                       \
        }                                                                       \
    } while (0)

static void write_file(const char *path, const char *contents, mode_t mode) {
    FILE *file = fopen(path, "wb");
    if (file == NULL) {
        perror(path);
        exit(1);
    }
    fputs(contents, file);
    fclose(file);
    if (chmod(path, mode) != 0) {
        perror(path);
        exit(1);
    }
}

static void make_dir(const char *path) {
    if (mkdir(path, 0755) != 0 && errno != EEXIST) {
        perror(path);
        exit(1);
    }
}

static long long monotonic_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
}

static void test_discovery_and_run(const char *base) {
    char plugin_dir[1024];
    char manifest[1024];
    char script[1024];
    snprintf(plugin_dir, sizeof plugin_dir, "%s/ok", base);
    snprintf(manifest, sizeof manifest, "%s/manifest.json", plugin_dir);
    snprintf(script, sizeof script, "%s/ok.sh", plugin_dir);
    make_dir(plugin_dir);
    write_file(manifest,
               "{\"id\":\"ok\",\"name\":\"OK\",\"version\":\"0.1.0\","
               "\"type\":\"post-process\",\"exec\":\"ok.sh\",\"timeout_ms\":5000}\n",
               0644);
    write_file(script,
               "#!/bin/sh\n"
               "cat >/dev/null\n"
               "echo '{\"ok\":true,\"message\":\"fine\",\"clipboard_text\":\"hello\"}'\n",
               0755);

    slim_plugin_list_t list;
    slim_plugins_init(&list);
    char err[256] = { 0 };
    int result = slim_plugins_discover(&list, base, NULL, err, sizeof err);
    CHECK(result == 0);
    CHECK(list.count == 1);
    CHECK(strcmp(list.items[0].id, "ok") == 0);
    CHECK(strcmp(list.items[0].name, "OK") == 0);
    CHECK(list.items[0].type == SLIM_PLUGIN_POST_PROCESS);
    CHECK(list.items[0].timeout_ms == 5000);
    CHECK(list.items[0].builtin == 1);

    char *out = NULL;
    char *stderr_text = NULL;
    err[0] = '\0';
    result = slim_plugin_run(&list.items[0], "{\"image_path\":\"/tmp/x.png\"}",
                             &out, &stderr_text, err, sizeof err);
    CHECK(result == 0);
    CHECK(out != NULL && strstr(out, "\"ok\":true") != NULL);
    CHECK(out != NULL && strstr(out, "hello") != NULL);
    CHECK(stderr_text != NULL && stderr_text[0] == '\0');
    free(out);
    free(stderr_text);
    slim_plugins_free(&list);
}

static void test_timeout(const char *base) {
    char plugin_dir[1024];
    char manifest[1024];
    char script[1024];
    snprintf(plugin_dir, sizeof plugin_dir, "%s/slow", base);
    snprintf(manifest, sizeof manifest, "%s/manifest.json", plugin_dir);
    snprintf(script, sizeof script, "%s/slow.sh", plugin_dir);
    make_dir(plugin_dir);
    write_file(manifest,
               "{\"id\":\"slow\",\"name\":\"Slow\",\"version\":\"0.1.0\","
               "\"type\":\"post-process\",\"exec\":\"slow.sh\",\"timeout_ms\":1000}\n",
               0644);
    write_file(script, "#!/bin/sh\ncat >/dev/null\nsleep 5\n", 0755);

    slim_plugin_list_t list;
    slim_plugins_init(&list);
    char err[256] = { 0 };
    int result = slim_plugins_discover(&list, base, NULL, err, sizeof err);
    CHECK(result == 0);
    CHECK(list.count == 1);

    char *out = NULL;
    char *stderr_text = NULL;
    err[0] = '\0';
    long long start = monotonic_ms();
    result = slim_plugin_run(&list.items[0], "{\"image_path\":\"/tmp/x.png\"}",
                             &out, &stderr_text, err, sizeof err);
    long long elapsed = monotonic_ms() - start;
    CHECK(result != 0);
    CHECK(strstr(err, "timed out") != NULL);
    CHECK(elapsed >= 900 && elapsed < 4000);
    free(out);
    free(stderr_text);
    slim_plugins_free(&list);
}

static void test_failure(const char *base) {
    char plugin_dir[1024];
    char manifest[1024];
    char script[1024];
    snprintf(plugin_dir, sizeof plugin_dir, "%s/bad", base);
    snprintf(manifest, sizeof manifest, "%s/manifest.json", plugin_dir);
    snprintf(script, sizeof script, "%s/bad.sh", plugin_dir);
    make_dir(plugin_dir);
    write_file(manifest,
               "{\"id\":\"bad\",\"name\":\"Bad\",\"version\":\"0.1.0\","
               "\"type\":\"post-process\",\"exec\":\"bad.sh\",\"timeout_ms\":5000}\n",
               0644);
    write_file(script, "#!/bin/sh\ncat >/dev/null\necho boom >&2\nexit 3\n", 0755);

    slim_plugin_list_t list;
    slim_plugins_init(&list);
    char err[256] = { 0 };
    int result = slim_plugins_discover(&list, base, NULL, err, sizeof err);
    CHECK(result == 0);
    CHECK(list.count == 1);

    char *out = NULL;
    char *stderr_text = NULL;
    err[0] = '\0';
    result = slim_plugin_run(&list.items[0], "{\"image_path\":\"/tmp/x.png\"}",
                             &out, &stderr_text, err, sizeof err);
    CHECK(result != 0);
    CHECK(strstr(err, "status 3") != NULL);
    CHECK(stderr_text != NULL && strstr(stderr_text, "boom") != NULL);
    free(out);
    free(stderr_text);
    slim_plugins_free(&list);
}

static void test_invalid_manifest(const char *base) {
    char plugin_dir[1024];
    char manifest[1024];
    snprintf(plugin_dir, sizeof plugin_dir, "%s/broken", base);
    snprintf(manifest, sizeof manifest, "%s/manifest.json", plugin_dir);
    make_dir(plugin_dir);
    write_file(manifest, "{\"id\":\"broken\"}\n", 0644);

    slim_plugin_list_t list;
    slim_plugins_init(&list);
    char err[256] = { 0 };
    int result = slim_plugins_discover(&list, base, NULL, err, sizeof err);
    CHECK(result == 0);
    CHECK(list.count == 0);
    slim_plugins_free(&list);
}

int main(void) {
    char base_ok[] = "/tmp/slimshot-plugin-ok.XXXXXX";
    char base_timeout[] = "/tmp/slimshot-plugin-timeout.XXXXXX";
    char base_failure[] = "/tmp/slimshot-plugin-failure.XXXXXX";
    char base_invalid[] = "/tmp/slimshot-plugin-invalid.XXXXXX";
    if (mkdtemp(base_ok) == NULL || mkdtemp(base_timeout) == NULL ||
        mkdtemp(base_failure) == NULL || mkdtemp(base_invalid) == NULL) {
        perror("mkdtemp");
        return 1;
    }

    test_discovery_and_run(base_ok);
    test_timeout(base_timeout);
    test_failure(base_failure);
    test_invalid_manifest(base_invalid);

    char command[1200];
    snprintf(command, sizeof command, "rm -rf '%s' '%s' '%s' '%s'",
             base_ok, base_timeout, base_failure, base_invalid);
    (void)system(command);

    if (g_failures != 0) {
        fprintf(stderr, "plugin_test: %d failure(s)\n", g_failures);
        return 1;
    }
    printf("plugin_test: OK\n");
    return 0;
}
