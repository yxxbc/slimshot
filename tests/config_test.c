/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "config.h"
#include "naming.h"
#include "paths.h"

static void write_file(const char *path, const char *text) {
    FILE *file = fopen(path, "wb");
    assert(file != NULL);
    size_t len = strlen(text);
    assert(fwrite(text, 1, len, file) == len);
    assert(fclose(file) == 0);
}

int main(void) {
    char dir[SLIM_PATH_MAX];
    (void)snprintf(dir, sizeof dir, "/tmp/slimshot-config-test-%d", (int)getpid());
    (void)rmdir(dir);
    assert(mkdir(dir, 0700) == 0);

    char path[SLIM_PATH_MAX];
    (void)snprintf(path, sizeof path, "%s/sub/config.json", dir);

    slim_config_t written;
    slim_config_defaults(&written);
    assert(written.copy_to_clipboard == 1);
    assert(written.auto_save == 1);
    assert(strcmp(written.format, "png") == 0);
    assert(strcmp(written.hotkey_region, "cmd+shift+a") == 0);

    written.copy_to_clipboard = 0;
    written.jpeg_quality = 77;
    (void)snprintf(written.format, sizeof written.format, "heic");
    (void)snprintf(written.save_directory, sizeof written.save_directory,
                   "~/Pictures/Screenshots");

    char err[256] = { 0 };
    assert(slim_config_save_to_path(&written, path, err, sizeof err) == 0);

    slim_config_t loaded;
    assert(slim_config_load_from_path(&loaded, path, err, sizeof err) == 0);
    assert(loaded.copy_to_clipboard == 0);
    assert(loaded.auto_save == 1);
    assert(loaded.jpeg_quality == 77);
    assert(strcmp(loaded.format, "heic") == 0);
    assert(strcmp(loaded.save_directory, "~/Pictures/Screenshots") == 0);
    assert(strcmp(loaded.hotkey_region, "cmd+shift+a") == 0);

    write_file(path, "{ this is not valid json");
    slim_config_t invalid;
    assert(slim_config_load_from_path(&invalid, path, err, sizeof err) != 0);
    assert(invalid.copy_to_clipboard == 1);
    assert(strcmp(invalid.format, "png") == 0);

    char expanded[SLIM_PATH_MAX];
    assert(slim_paths_expand_tilde("~/Pictures", expanded, sizeof expanded) == 0);
    const char *home = getenv("HOME");
    assert(home != NULL);
    assert(strncmp(expanded, home, strlen(home)) == 0);
    assert(strcmp(expanded + strlen(home), "/Pictures") == 0);

    struct tm fixed;
    memset(&fixed, 0, sizeof fixed);
    fixed.tm_year = 126;
    fixed.tm_mon = 10;
    fixed.tm_mday = 3;
    fixed.tm_hour = 21;
    fixed.tm_min = 56;
    fixed.tm_sec = 0;

    char name[SLIM_PATH_MAX];
    assert(slim_naming_format("Slimshot-{yyyy}-{MM}-{dd}_{HH}-{mm}-{ss}",
                              &fixed, "png", name, sizeof name) == 0);
    assert(strcmp(name, "Slimshot-2026-11-03_21-56-00.png") == 0);

    assert(slim_naming_format("shot-{unknown}-{yyyy}", &fixed, "jpg",
                              name, sizeof name) == 0);
    assert(strcmp(name, "shot-{unknown}-2026.jpg") == 0);

    char existing[SLIM_PATH_MAX];
    (void)snprintf(existing, sizeof existing, "%s/a.png", dir);
    write_file(existing, "x");

    char unique[SLIM_PATH_MAX];
    assert(slim_naming_unique(existing, unique, sizeof unique) == 0);
    char expected_unique[SLIM_PATH_MAX];
    (void)snprintf(expected_unique, sizeof expected_unique, "%s/a-1.png", dir);
    assert(strcmp(unique, expected_unique) == 0);

    char sub[SLIM_PATH_MAX];
    (void)snprintf(sub, sizeof sub, "%s/sub", dir);
    (void)unlink(existing);
    (void)unlink(path);
    (void)rmdir(sub);
    (void)rmdir(dir);

    printf("config_test: OK\n");
    return 0;
}
