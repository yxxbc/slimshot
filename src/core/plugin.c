/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#include "plugin.h"

#include "cJSON.h"
#include "log.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

#define SLIM_PLUGIN_MAX_OUTPUT (8u * 1024u * 1024u)
#define SLIM_PLUGIN_MAX_STDERR (512u * 1024u)
#define SLIM_PLUGIN_MAX_MANIFEST (64u * 1024u)
#define SLIM_PLUGIN_DEFAULT_TIMEOUT_MS 15000

static void set_err(char *err, size_t errlen, const char *fmt, ...) {
    if (err == NULL || errlen == 0) {
        return;
    }
    va_list args;
    va_start(args, fmt);
    (void)vsnprintf(err, errlen, fmt, args);
    va_end(args);
}

static int copy_string(char *dst, size_t len, const char *src) {
    if (src == NULL) {
        return -1;
    }
    size_t n = strlen(src);
    if (n == 0 || n >= len) {
        return -1;
    }
    memcpy(dst, src, n + 1);
    return 0;
}

static int valid_id(const char *id) {
    if (id == NULL || id[0] == '\0') {
        return 0;
    }
    size_t len = strlen(id);
    if (len >= SLIM_PLUGIN_ID_MAX) {
        return 0;
    }
    for (size_t i = 0; i < len; i++) {
        char c = id[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-')) {
            return 0;
        }
    }
    return 1;
}

static int valid_exec(const char *exec) {
    if (exec == NULL || exec[0] == '\0' || exec[0] == '/') {
        return 0;
    }
    return strstr(exec, "..") == NULL;
}

static int read_file(const char *path, char **out, size_t *outlen) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return -1;
    }
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return -1;
    }
    long size = ftell(file);
    if (size < 0 || (unsigned long)size > SLIM_PLUGIN_MAX_MANIFEST) {
        fclose(file);
        return -1;
    }
    rewind(file);
    char *buffer = malloc((size_t)size + 1);
    if (buffer == NULL) {
        fclose(file);
        return -1;
    }
    size_t read = fread(buffer, 1, (size_t)size, file);
    fclose(file);
    if (read != (size_t)size) {
        free(buffer);
        return -1;
    }
    buffer[read] = '\0';
    *out = buffer;
    *outlen = read;
    return 0;
}

static int load_manifest(const char *plugin_dir, const char *manifest_path,
                         int builtin, slim_plugin_t *out) {
    char *json = NULL;
    size_t length = 0;
    if (read_file(manifest_path, &json, &length) != 0) {
        return -1;
    }
    cJSON *root = cJSON_ParseWithLength(json, length);
    free(json);
    if (root == NULL) {
        return -1;
    }

    int ok = 0;
    cJSON *id = cJSON_GetObjectItemCaseSensitive(root, "id");
    cJSON *name = cJSON_GetObjectItemCaseSensitive(root, "name");
    cJSON *version = cJSON_GetObjectItemCaseSensitive(root, "version");
    cJSON *type = cJSON_GetObjectItemCaseSensitive(root, "type");
    cJSON *exec = cJSON_GetObjectItemCaseSensitive(root, "exec");
    cJSON *timeout = cJSON_GetObjectItemCaseSensitive(root, "timeout_ms");

    if (cJSON_IsString(id) && valid_id(id->valuestring) &&
        cJSON_IsString(name) && name->valuestring[0] != '\0' &&
        cJSON_IsString(type) && cJSON_IsString(exec) &&
        valid_exec(exec->valuestring)) {
        slim_plugin_t plugin;
        memset(&plugin, 0, sizeof plugin);
        if (copy_string(plugin.id, sizeof plugin.id, id->valuestring) == 0 &&
            copy_string(plugin.name, sizeof plugin.name, name->valuestring) == 0 &&
            copy_string(plugin.version, sizeof plugin.version,
                        (cJSON_IsString(version) && version->valuestring[0] != '\0')
                            ? version->valuestring
                            : "0.0.0") == 0 &&
            copy_string(plugin.directory, sizeof plugin.directory, plugin_dir) == 0) {
            if (strcmp(type->valuestring, "post-process") == 0) {
                plugin.type = SLIM_PLUGIN_POST_PROCESS;
            } else if (strcmp(type->valuestring, "standalone") == 0) {
                plugin.type = SLIM_PLUGIN_STANDALONE;
            }
            int valid_type = (strcmp(type->valuestring, "post-process") == 0 ||
                              strcmp(type->valuestring, "standalone") == 0);
            if (valid_type) {
                int timeout_ms = SLIM_PLUGIN_DEFAULT_TIMEOUT_MS;
                if (cJSON_IsNumber(timeout)) {
                    timeout_ms = timeout->valueint;
                    if (timeout_ms < 1000) {
                        timeout_ms = 1000;
                    }
                    if (timeout_ms > 600000) {
                        timeout_ms = 600000;
                    }
                }
                plugin.timeout_ms = timeout_ms;
                plugin.builtin = builtin ? 1 : 0;
                int written = snprintf(plugin.exec_path, sizeof plugin.exec_path,
                                       "%s/%s", plugin_dir, exec->valuestring);
                if (written > 0 && (size_t)written < sizeof plugin.exec_path &&
                    access(plugin.exec_path, X_OK) == 0) {
                    *out = plugin;
                    ok = 1;
                }
            }
        }
    }

    cJSON_Delete(root);
    return ok ? 0 : -1;
}

static void list_add(slim_plugin_list_t *list, const slim_plugin_t *plugin) {
    for (size_t i = 0; i < list->count; i++) {
        if (strcmp(list->items[i].id, plugin->id) == 0) {
            if (!plugin->builtin && list->items[i].builtin) {
                list->items[i] = *plugin;
            }
            return;
        }
    }
    slim_plugin_t *items =
        realloc(list->items, (list->count + 1) * sizeof *items);
    if (items == NULL) {
        return;
    }
    list->items = items;
    list->items[list->count++] = *plugin;
}

static void scan_dir(slim_plugin_list_t *list, const char *dir, int builtin) {
    if (dir == NULL || dir[0] == '\0') {
        return;
    }
    DIR *handle = opendir(dir);
    if (handle == NULL) {
        if (errno != ENOENT) {
            slim_log("plugin dir %s: %s", dir, strerror(errno));
        }
        return;
    }

    struct dirent *entry = NULL;
    while ((entry = readdir(handle)) != NULL) {
        if (entry->d_name[0] == '.') {
            continue;
        }
        char plugin_dir[SLIM_PATH_MAX * 2];
        int n = snprintf(plugin_dir, sizeof plugin_dir, "%s/%s",
                         dir, entry->d_name);
        if (n <= 0 || (size_t)n >= sizeof plugin_dir) {
            continue;
        }
        struct stat info;
        if (stat(plugin_dir, &info) != 0 || !S_ISDIR(info.st_mode)) {
            continue;
        }
        char manifest[SLIM_PATH_MAX * 3];
        n = snprintf(manifest, sizeof manifest, "%s/manifest.json", plugin_dir);
        if (n <= 0 || (size_t)n >= sizeof manifest) {
            continue;
        }
        slim_plugin_t plugin;
        if (load_manifest(plugin_dir, manifest, builtin, &plugin) == 0) {
            list_add(list, &plugin);
        } else {
            slim_log("plugin skipped: %s", manifest);
        }
    }
    closedir(handle);
}

static int compare_plugins(const void *a, const void *b) {
    const slim_plugin_t *pa = a;
    const slim_plugin_t *pb = b;
    int cmp = strcasecmp(pa->name, pb->name);
    if (cmp != 0) {
        return cmp;
    }
    return strcasecmp(pa->id, pb->id);
}

void slim_plugins_init(slim_plugin_list_t *list) {
    if (list != NULL) {
        memset(list, 0, sizeof *list);
    }
}

void slim_plugins_free(slim_plugin_list_t *list) {
    if (list == NULL) {
        return;
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
}

int slim_plugins_discover(slim_plugin_list_t *list,
                          const char *builtin_dir,
                          const char *user_dir,
                          char *err, size_t errlen) {
    if (list == NULL) {
        set_err(err, errlen, "invalid plugin list");
        return -1;
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;

    scan_dir(list, builtin_dir, 1);
    scan_dir(list, user_dir, 0);
    if (list->count > 1) {
        qsort(list->items, list->count, sizeof *list->items, compare_plugins);
    }
    return 0;
}

const char *slim_plugin_type_name(slim_plugin_type_t type) {
    return (type == SLIM_PLUGIN_STANDALONE) ? "standalone" : "post-process";
}

static int set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) {
        return -1;
    }
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

static int append_bytes(char **buffer, size_t *length, size_t *capacity,
                        const char *data, size_t count, size_t max) {
    if (*length + count + 1 > max) {
        return -1;
    }
    if (*length + count + 1 > *capacity) {
        size_t next = (*capacity > 0) ? *capacity * 2 : 8192;
        while (next < *length + count + 1) {
            next *= 2;
        }
        char *grown = realloc(*buffer, next);
        if (grown == NULL) {
            return -1;
        }
        *buffer = grown;
        *capacity = next;
    }
    memcpy(*buffer + *length, data, count);
    *length += count;
    (*buffer)[*length] = '\0';
    return 0;
}

static long long monotonic_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL;
}

static void close_fd(int *fd) {
    if (*fd >= 0) {
        close(*fd);
        *fd = -1;
    }
}

int slim_plugin_run(const slim_plugin_t *plugin,
                    const char *request_json,
                    char **stdout_text,
                    char **stderr_text,
                    char *err, size_t errlen) {
    if (stdout_text != NULL) {
        *stdout_text = NULL;
    }
    if (stderr_text != NULL) {
        *stderr_text = NULL;
    }
    if (plugin == NULL || request_json == NULL) {
        set_err(err, errlen, "invalid plugin input");
        return -1;
    }
    size_t request_length = strlen(request_json);
    if (request_length > 256u * 1024u) {
        set_err(err, errlen, "plugin request too large");
        return -1;
    }

    int input_pipe[2] = { -1, -1 };
    int output_pipe[2] = { -1, -1 };
    int error_pipe[2] = { -1, -1 };
    if (pipe(input_pipe) != 0 || pipe(output_pipe) != 0 || pipe(error_pipe) != 0) {
        set_err(err, errlen, "pipe: %s", strerror(errno));
        close_fd(&input_pipe[0]);
        close_fd(&input_pipe[1]);
        close_fd(&output_pipe[0]);
        close_fd(&output_pipe[1]);
        close_fd(&error_pipe[0]);
        close_fd(&error_pipe[1]);
        return -1;
    }

    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    posix_spawn_file_actions_init(&actions);
    posix_spawnattr_init(&attributes);
    posix_spawn_file_actions_adddup2(&actions, input_pipe[0], STDIN_FILENO);
    posix_spawn_file_actions_adddup2(&actions, output_pipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, error_pipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, input_pipe[0]);
    posix_spawn_file_actions_addclose(&actions, input_pipe[1]);
    posix_spawn_file_actions_addclose(&actions, output_pipe[0]);
    posix_spawn_file_actions_addclose(&actions, output_pipe[1]);
    posix_spawn_file_actions_addclose(&actions, error_pipe[0]);
    posix_spawn_file_actions_addclose(&actions, error_pipe[1]);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attributes, 0);

    char *argv[] = { (char *)plugin->exec_path, NULL };
    pid_t pid = 0;
    int spawn_error = posix_spawn(&pid, plugin->exec_path, &actions,
                                  &attributes, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);

    if (spawn_error != 0) {
        set_err(err, errlen, "spawn %s: %s", plugin->exec_path,
                strerror(spawn_error));
        close_fd(&input_pipe[0]);
        close_fd(&input_pipe[1]);
        close_fd(&output_pipe[0]);
        close_fd(&output_pipe[1]);
        close_fd(&error_pipe[0]);
        close_fd(&error_pipe[1]);
        return -1;
    }

    close_fd(&input_pipe[0]);
    close_fd(&output_pipe[1]);
    close_fd(&error_pipe[1]);

    size_t written = 0;
    while (written < request_length) {
        ssize_t count = write(input_pipe[1], request_json + written,
                              request_length - written);
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (errno == EPIPE) {
                break;
            }
            break;
        }
        written += (size_t)count;
    }
    close_fd(&input_pipe[1]);

    (void)set_nonblocking(output_pipe[0]);
    (void)set_nonblocking(error_pipe[0]);

    char *out_buffer = NULL;
    char *err_buffer = NULL;
    size_t out_length = 0;
    size_t err_length = 0;
    size_t out_capacity = 0;
    size_t err_capacity = 0;
    int out_open = 1;
    int err_open = 1;
    int timed_out = 0;
    int read_failed = 0;

    int timeout_ms = (plugin->timeout_ms > 0)
                         ? plugin->timeout_ms
                         : SLIM_PLUGIN_DEFAULT_TIMEOUT_MS;
    long long deadline = monotonic_ms() + timeout_ms;

    while (out_open || err_open) {
        struct pollfd fds[2];
        int count = 0;
        if (out_open) {
            fds[count].fd = output_pipe[0];
            fds[count].events = POLLIN;
            fds[count].revents = 0;
            count++;
        }
        if (err_open) {
            fds[count].fd = error_pipe[0];
            fds[count].events = POLLIN;
            fds[count].revents = 0;
            count++;
        }

        long long remaining = deadline - monotonic_ms();
        if (remaining < 0) {
            remaining = 0;
        }
        int polled = poll(fds, (nfds_t)count, (int)remaining);
        if (polled < 0) {
            if (errno == EINTR) {
                continue;
            }
            read_failed = 1;
            break;
        }
        if (polled == 0) {
            timed_out = 1;
            break;
        }

        for (int i = 0; i < count; i++) {
            if ((fds[i].revents & (POLLIN | POLLHUP | POLLERR)) == 0) {
                continue;
            }
            int is_output = (out_open && fds[i].fd == output_pipe[0]);
            char chunk[4096];
            ssize_t read_count = read(fds[i].fd, chunk, sizeof chunk);
            if (read_count > 0) {
                int appended = is_output
                                   ? append_bytes(&out_buffer, &out_length,
                                                  &out_capacity, chunk,
                                                  (size_t)read_count,
                                                  SLIM_PLUGIN_MAX_OUTPUT)
                                   : append_bytes(&err_buffer, &err_length,
                                                  &err_capacity, chunk,
                                                  (size_t)read_count,
                                                  SLIM_PLUGIN_MAX_STDERR);
                if (appended != 0) {
                    read_failed = 1;
                    break;
                }
            } else if (read_count == 0) {
                if (is_output) {
                    close_fd(&output_pipe[0]);
                    out_open = 0;
                } else {
                    close_fd(&error_pipe[0]);
                    err_open = 0;
                }
            } else if (errno != EAGAIN && errno != EWOULDBLOCK &&
                       errno != EINTR) {
                if (is_output) {
                    close_fd(&output_pipe[0]);
                    out_open = 0;
                } else {
                    close_fd(&error_pipe[0]);
                    err_open = 0;
                }
            }
        }
        if (read_failed) {
            break;
        }
    }

    if (timed_out) {
        set_err(err, errlen, "plugin timed out after %d ms", timeout_ms);
    } else if (read_failed) {
        set_err(err, errlen, "plugin output error");
    }

    if (timed_out || read_failed) {
        kill(-pid, SIGKILL);
        kill(pid, SIGKILL);
    }

    int status = 0;
    int exited = 0;
    for (int i = 0; i < 200; i++) {
        pid_t result = waitpid(pid, &status, WNOHANG);
        if (result == pid) {
            exited = 1;
            break;
        }
        if (result < 0 && errno != EINTR) {
            exited = 1;
            status = 0;
            break;
        }
        struct timespec pause = { 0, 5 * 1000 * 1000 };
        nanosleep(&pause, NULL);
    }
    if (!exited) {
        kill(-pid, SIGKILL);
        kill(pid, SIGKILL);
        (void)waitpid(pid, &status, 0);
    }

    close_fd(&output_pipe[0]);
    close_fd(&error_pipe[0]);

    if (out_buffer == NULL) {
        out_buffer = calloc(1, 1);
    }
    if (err_buffer == NULL) {
        err_buffer = calloc(1, 1);
    }
    if (stdout_text != NULL) {
        *stdout_text = out_buffer;
        out_buffer = NULL;
    }
    if (stderr_text != NULL) {
        *stderr_text = err_buffer;
        err_buffer = NULL;
    }
    free(out_buffer);
    free(err_buffer);

    if (timed_out || read_failed) {
        return -1;
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        set_err(err, errlen, "plugin exited with status %d",
                WIFEXITED(status) ? WEXITSTATUS(status) : -1);
        return -1;
    }
    return 0;
}
