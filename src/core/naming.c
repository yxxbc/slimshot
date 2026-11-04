/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#include "naming.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int append_text(char *out, size_t len, size_t *used, const char *text) {
    size_t n = strlen(text);
    if (*used + n >= len) {
        return -1;
    }
    memcpy(out + *used, text, n);
    *used += n;
    out[*used] = '\0';
    return 0;
}

static int append_char(char *out, size_t len, size_t *used, char c) {
    if (*used + 1 >= len) {
        return -1;
    }
    out[(*used)++] = c;
    out[*used] = '\0';
    return 0;
}

const char *slim_format_extension(const char *format) {
    if (format == NULL) {
        return "png";
    }
    if (strcmp(format, "jpeg") == 0) {
        return "jpg";
    }
    if (strcmp(format, "heic") == 0) {
        return "heic";
    }
    if (strcmp(format, "tiff") == 0) {
        return "tiff";
    }
    return "png";
}

int slim_naming_format(const char *template_str, const struct tm *tm,
                       const char *extension, char *out, size_t len) {
    if (out == NULL || len == 0 || tm == NULL) {
        return -1;
    }
    if (template_str == NULL || template_str[0] == '\0') {
        template_str = "Slimshot-{yyyy}-{MM}-{dd}_{HH}-{mm}-{ss}";
    }

    size_t used = 0;
    out[0] = '\0';

    for (const char *p = template_str; *p != '\0';) {
        if (*p == '{') {
            const char *end = strchr(p, '}');
            if (end != NULL) {
                size_t token_len = (size_t)(end - p - 1);
                char token[16];
                if (token_len < sizeof token) {
                    memcpy(token, p + 1, token_len);
                    token[token_len] = '\0';

                    char value[16];
                    int known = 1;
                    if (strcmp(token, "yyyy") == 0) {
                        (void)snprintf(value, sizeof value, "%04d", tm->tm_year + 1900);
                    } else if (strcmp(token, "MM") == 0) {
                        (void)snprintf(value, sizeof value, "%02d", tm->tm_mon + 1);
                    } else if (strcmp(token, "dd") == 0) {
                        (void)snprintf(value, sizeof value, "%02d", tm->tm_mday);
                    } else if (strcmp(token, "HH") == 0) {
                        (void)snprintf(value, sizeof value, "%02d", tm->tm_hour);
                    } else if (strcmp(token, "mm") == 0) {
                        (void)snprintf(value, sizeof value, "%02d", tm->tm_min);
                    } else if (strcmp(token, "ss") == 0) {
                        (void)snprintf(value, sizeof value, "%02d", tm->tm_sec);
                    } else {
                        known = 0;
                    }

                    if (known) {
                        if (append_text(out, len, &used, value) != 0) {
                            return -1;
                        }
                        p = end + 1;
                        continue;
                    }
                }
            }
        }
        if (append_char(out, len, &used, *p) != 0) {
            return -1;
        }
        p++;
    }

    if (extension != NULL && extension[0] != '\0') {
        if (extension[0] != '.') {
            if (append_char(out, len, &used, '.') != 0) {
                return -1;
            }
        }
        if (append_text(out, len, &used, extension) != 0) {
            return -1;
        }
    }
    return 0;
}

int slim_naming_make(const slim_config_t *cfg, const char *extension,
                     char *out, size_t len) {
    if (cfg == NULL) {
        return -1;
    }
    time_t now = time(NULL);
    struct tm tm_now;
    if (localtime_r(&now, &tm_now) == NULL) {
        return -1;
    }
    const char *ext = (extension != NULL) ? extension : slim_format_extension(cfg->format);
    return slim_naming_format(cfg->filename_template, &tm_now, ext, out, len);
}

int slim_naming_unique(const char *path, char *out, size_t len) {
    if (path == NULL || out == NULL || len == 0) {
        return -1;
    }
    if (access(path, F_OK) != 0) {
        int n = snprintf(out, len, "%s", path);
        return (n < 0 || (size_t)n >= len) ? -1 : 0;
    }

    const char *slash = strrchr(path, '/');
    const char *base = (slash != NULL) ? slash + 1 : path;
    const char *dot = strrchr(base, '.');

    for (int i = 1; i < 1000; i++) {
        int n;
        if (dot != NULL) {
            n = snprintf(out, len, "%.*s-%d%s", (int)(dot - path), path, i, dot);
        } else {
            n = snprintf(out, len, "%s-%d", path, i);
        }
        if (n < 0 || (size_t)n >= len) {
            return -1;
        }
        if (access(out, F_OK) != 0) {
            return 0;
        }
    }
    return -1;
}
