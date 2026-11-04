/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#include "config.h"

#include "cJSON.h"

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void set_err(char *err, size_t errlen, const char *fmt, ...) {
    if (err == NULL || errlen == 0) {
        return;
    }
    va_list ap;
    va_start(ap, fmt);
    (void)vsnprintf(err, errlen, fmt, ap);
    va_end(ap);
}

static void copy_string(char *dst, size_t len, const char *src) {
    if (src == NULL || len == 0) {
        return;
    }
    (void)snprintf(dst, len, "%s", src);
}

static int clamp_int(int value, int lo, int hi) {
    if (value < lo) {
        return lo;
    }
    if (value > hi) {
        return hi;
    }
    return value;
}

static int json_int(const cJSON *root, const char *key, int def) {
    const cJSON *item = cJSON_GetObjectItemCaseSensitive(root, key);
    if (cJSON_IsNumber(item)) {
        return item->valueint;
    }
    if (cJSON_IsBool(item)) {
        return cJSON_IsTrue(item) ? 1 : 0;
    }
    return def;
}

static int json_bool(const cJSON *root, const char *key, int def) {
    return json_int(root, key, def) ? 1 : 0;
}

static const char *json_string(const cJSON *root, const char *key) {
    const cJSON *item = cJSON_GetObjectItemCaseSensitive(root, key);
    return cJSON_IsString(item) ? item->valuestring : NULL;
}

static int valid_format(const char *fmt) {
    return strcmp(fmt, "png") == 0 || strcmp(fmt, "jpeg") == 0 ||
           strcmp(fmt, "heic") == 0 || strcmp(fmt, "tiff") == 0;
}

static int valid_language(const char *lang) {
    return strcmp(lang, "system") == 0 || strcmp(lang, "en") == 0 ||
           strcmp(lang, "zh-Hans") == 0;
}

void slim_config_defaults(slim_config_t *cfg) {
    if (cfg == NULL) {
        return;
    }
    memset(cfg, 0, sizeof *cfg);
    cfg->version = 1;
    cfg->copy_to_clipboard = 1;
    cfg->auto_save = 1;
    cfg->include_cursor = 0;
    cfg->show_thumbnail = 1;
    cfg->thumbnail_seconds = 3;
    cfg->launch_at_login = 0;
    copy_string(cfg->save_directory, sizeof cfg->save_directory, "~/Pictures/Screenshots");
    copy_string(cfg->filename_template, sizeof cfg->filename_template,
                "Slimshot-{yyyy}-{MM}-{dd}_{HH}-{mm}-{ss}");
    copy_string(cfg->format, sizeof cfg->format, "png");
    cfg->jpeg_quality = 90;
    cfg->heic_quality = 90;
    copy_string(cfg->language, sizeof cfg->language, "system");
    copy_string(cfg->hotkey_fullscreen, sizeof cfg->hotkey_fullscreen, "alt+shift+1");
    copy_string(cfg->hotkey_window, sizeof cfg->hotkey_window, "alt+shift+2");
    copy_string(cfg->hotkey_region, sizeof cfg->hotkey_region, "cmd+shift+a");
}

int slim_config_load_from_path(slim_config_t *cfg, const char *path, char *err, size_t errlen) {
    if (cfg == NULL || path == NULL) {
        set_err(err, errlen, "invalid arguments");
        return -1;
    }

    slim_config_defaults(cfg);

    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        set_err(err, errlen, "open %s: %s", path, strerror(errno));
        return -1;
    }

    if (fseek(file, 0, SEEK_END) != 0) {
        set_err(err, errlen, "seek %s: %s", path, strerror(errno));
        (void)fclose(file);
        return -1;
    }
    long size = ftell(file);
    if (size < 0 || size > 4 * 1024 * 1024) {
        set_err(err, errlen, "invalid config size for %s", path);
        (void)fclose(file);
        return -1;
    }
    rewind(file);

    char *buf = (char *)malloc((size_t)size + 1);
    if (buf == NULL) {
        set_err(err, errlen, "out of memory reading %s", path);
        (void)fclose(file);
        return -1;
    }

    size_t got = fread(buf, 1, (size_t)size, file);
    (void)fclose(file);
    if (got != (size_t)size) {
        set_err(err, errlen, "short read from %s", path);
        free(buf);
        return -1;
    }
    buf[size] = '\0';

    cJSON *root = cJSON_Parse(buf);
    if (root == NULL) {
        const char *where = cJSON_GetErrorPtr();
        set_err(err, errlen, "JSON parse error in %s near %s", path,
                where != NULL ? where : "(unknown)");
        free(buf);
        return -1;
    }

    cfg->version = json_int(root, "version", cfg->version);
    cfg->copy_to_clipboard = json_bool(root, "copy_to_clipboard", cfg->copy_to_clipboard);
    cfg->auto_save = json_bool(root, "auto_save", cfg->auto_save);
    cfg->include_cursor = json_bool(root, "include_cursor", cfg->include_cursor);
    cfg->show_thumbnail = json_bool(root, "show_thumbnail", cfg->show_thumbnail);
    cfg->thumbnail_seconds =
        clamp_int(json_int(root, "thumbnail_seconds", cfg->thumbnail_seconds), 0, 60);
    cfg->launch_at_login = json_bool(root, "launch_at_login", cfg->launch_at_login);

    const char *value = json_string(root, "save_directory");
    if (value != NULL && value[0] != '\0') {
        copy_string(cfg->save_directory, sizeof cfg->save_directory, value);
    }
    value = json_string(root, "filename_template");
    if (value != NULL && value[0] != '\0') {
        copy_string(cfg->filename_template, sizeof cfg->filename_template, value);
    }
    value = json_string(root, "format");
    if (value != NULL && valid_format(value)) {
        copy_string(cfg->format, sizeof cfg->format, value);
    }
    cfg->jpeg_quality = clamp_int(json_int(root, "jpeg_quality", cfg->jpeg_quality), 1, 100);
    cfg->heic_quality = clamp_int(json_int(root, "heic_quality", cfg->heic_quality), 1, 100);
    value = json_string(root, "language");
    if (value != NULL && valid_language(value)) {
        copy_string(cfg->language, sizeof cfg->language, value);
    }
    value = json_string(root, "hotkey_fullscreen");
    if (value != NULL && value[0] != '\0') {
        copy_string(cfg->hotkey_fullscreen, sizeof cfg->hotkey_fullscreen, value);
    }
    value = json_string(root, "hotkey_window");
    if (value != NULL && value[0] != '\0') {
        copy_string(cfg->hotkey_window, sizeof cfg->hotkey_window, value);
    }
    value = json_string(root, "hotkey_region");
    if (value != NULL && value[0] != '\0') {
        copy_string(cfg->hotkey_region, sizeof cfg->hotkey_region, value);
    }

    cJSON_Delete(root);
    free(buf);
    return 0;
}

int slim_config_save_to_path(const slim_config_t *cfg, const char *path, char *err, size_t errlen) {
    if (cfg == NULL || path == NULL || path[0] == '\0') {
        set_err(err, errlen, "invalid arguments");
        return -1;
    }

    if (slim_mkdir_parent(path, 0755) != 0) {
        set_err(err, errlen, "create parent directory for %s: %s", path, strerror(errno));
        return -1;
    }

    cJSON *root = cJSON_CreateObject();
    if (root == NULL) {
        set_err(err, errlen, "out of memory creating config");
        return -1;
    }

    (void)cJSON_AddNumberToObject(root, "version", cfg->version);
    (void)cJSON_AddBoolToObject(root, "copy_to_clipboard", cfg->copy_to_clipboard != 0);
    (void)cJSON_AddBoolToObject(root, "auto_save", cfg->auto_save != 0);
    (void)cJSON_AddBoolToObject(root, "include_cursor", cfg->include_cursor != 0);
    (void)cJSON_AddBoolToObject(root, "show_thumbnail", cfg->show_thumbnail != 0);
    (void)cJSON_AddNumberToObject(root, "thumbnail_seconds", cfg->thumbnail_seconds);
    (void)cJSON_AddBoolToObject(root, "launch_at_login", cfg->launch_at_login != 0);
    (void)cJSON_AddStringToObject(root, "save_directory", cfg->save_directory);
    (void)cJSON_AddStringToObject(root, "filename_template", cfg->filename_template);
    (void)cJSON_AddStringToObject(root, "format", cfg->format);
    (void)cJSON_AddNumberToObject(root, "jpeg_quality", cfg->jpeg_quality);
    (void)cJSON_AddNumberToObject(root, "heic_quality", cfg->heic_quality);
    (void)cJSON_AddStringToObject(root, "language", cfg->language);
    (void)cJSON_AddStringToObject(root, "hotkey_fullscreen", cfg->hotkey_fullscreen);
    (void)cJSON_AddStringToObject(root, "hotkey_window", cfg->hotkey_window);
    (void)cJSON_AddStringToObject(root, "hotkey_region", cfg->hotkey_region);

    char *json = cJSON_Print(root);
    cJSON_Delete(root);
    if (json == NULL) {
        set_err(err, errlen, "out of memory serializing config");
        return -1;
    }

    char tmp_path[SLIM_PATH_MAX];
    int n = snprintf(tmp_path, sizeof tmp_path, "%s.tmp", path);
    if (n < 0 || (size_t)n >= sizeof tmp_path) {
        set_err(err, errlen, "config path too long: %s", path);
        cJSON_free(json);
        return -1;
    }

    FILE *file = fopen(tmp_path, "wb");
    if (file == NULL) {
        set_err(err, errlen, "open %s: %s", tmp_path, strerror(errno));
        cJSON_free(json);
        return -1;
    }

    size_t len = strlen(json);
    int ok = fwrite(json, 1, len, file) == len;
    if (ok) {
        ok = fputc('\n', file) != EOF;
    }
    if (ok) {
        ok = fflush(file) == 0;
    }
    if (ok) {
        (void)fsync(fileno(file));
    }
    if (fclose(file) != 0) {
        ok = 0;
    }
    cJSON_free(json);

    if (!ok) {
        set_err(err, errlen, "write %s: %s", tmp_path, strerror(errno));
        (void)unlink(tmp_path);
        return -1;
    }
    if (rename(tmp_path, path) != 0) {
        set_err(err, errlen, "replace %s: %s", path, strerror(errno));
        (void)unlink(tmp_path);
        return -1;
    }
    return 0;
}

int slim_config_load(slim_config_t *cfg, char *err, size_t errlen) {
    char dir[SLIM_PATH_MAX];
    if (slim_paths_app_support(dir, sizeof dir) != 0) {
        set_err(err, errlen, "cannot resolve Application Support path");
        return -1;
    }
    if (slim_mkdir_p(dir, 0755) != 0) {
        set_err(err, errlen, "create %s: %s", dir, strerror(errno));
        return -1;
    }

    char path[SLIM_PATH_MAX];
    if (slim_paths_config(path, sizeof path) != 0) {
        set_err(err, errlen, "cannot resolve config path");
        return -1;
    }

    if (access(path, F_OK) != 0) {
        slim_config_defaults(cfg);
        return slim_config_save_to_path(cfg, path, err, errlen);
    }
    return slim_config_load_from_path(cfg, path, err, errlen);
}

int slim_config_save(const slim_config_t *cfg, char *err, size_t errlen) {
    char path[SLIM_PATH_MAX];
    if (slim_paths_config(path, sizeof path) != 0) {
        set_err(err, errlen, "cannot resolve config path");
        return -1;
    }
    return slim_config_save_to_path(cfg, path, err, errlen);
}

int slim_config_path(char *buf, size_t len) {
    return slim_paths_config(buf, len);
}
