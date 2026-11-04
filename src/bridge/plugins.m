/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "log.h"
#include "paths.h"
#include "plugins.h"

@implementation SlimPlugin
@end

@implementation SlimPluginManager {
    NSArray<SlimPlugin *> *_plugins;
    BOOL _loaded;
    NSString *_lastImagePath;
    int _lastWidth;
    int _lastHeight;
    double _lastScale;
    NSString *_lastSource;
    NSDate *_lastCaptureDate;
}

+ (instancetype)sharedManager {
    static SlimPluginManager *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        manager = [[SlimPluginManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _lastScale = 1.0;
    }
    return self;
}

- (NSString *)builtinPluginDirectory {
    NSString *resources = [[NSBundle mainBundle] resourcePath];
    if (resources.length == 0) {
        return nil;
    }
    return [resources stringByAppendingPathComponent:@"Plugins"];
}

- (NSString *)userPluginDirectory {
    char directory[SLIM_PATH_MAX];
    if (slim_paths_app_support(directory, sizeof directory) != 0) {
        return nil;
    }
    NSString *base = [NSString stringWithUTF8String:directory];
    return (base != nil) ? [base stringByAppendingPathComponent:@"Plugins"] : nil;
}

- (void)reload {
    slim_plugin_list_t list;
    slim_plugins_init(&list);
    char err[256] = { 0 };
    NSString *builtin = [self builtinPluginDirectory];
    NSString *user = [self userPluginDirectory];
    (void)slim_plugins_discover(&list,
                                builtin.fileSystemRepresentation,
                                user.fileSystemRepresentation,
                                err, sizeof err);
    if (err[0] != '\0') {
        slim_log("plugin discovery: %s", err);
    }

    NSMutableArray<SlimPlugin *> *plugins =
        [NSMutableArray arrayWithCapacity:list.count];
    for (size_t i = 0; i < list.count; i++) {
        slim_plugin_t *item = &list.items[i];
        SlimPlugin *plugin = [[SlimPlugin alloc] init];
        plugin.identifier = [NSString stringWithUTF8String:item->id];
        plugin.name = [NSString stringWithUTF8String:item->name];
        plugin.version = [NSString stringWithUTF8String:item->version];
        plugin.iconName = (item->icon[0] != '\0')
                              ? [NSString stringWithUTF8String:item->icon]
                              : @"puzzlepiece.extension";
        plugin.type = item->type;
        plugin.execPath = [NSString stringWithUTF8String:item->exec_path];
        plugin.timeoutMs = item->timeout_ms;
        plugin.builtin = item->builtin != 0;
        if (plugin.identifier.length > 0 && plugin.execPath.length > 0) {
            [plugins addObject:plugin];
        }
    }
    slim_plugins_free(&list);

    _plugins = [plugins copy];
    _loaded = YES;
    slim_log("plugins discovered: %lu", (unsigned long)_plugins.count);
}

- (NSArray<SlimPlugin *> *)plugins {
    if (!_loaded) {
        [self reload];
    }
    return _plugins;
}

- (SlimPlugin *)pluginWithIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return nil;
    }
    for (SlimPlugin *plugin in self.plugins) {
        if ([plugin.identifier isEqualToString:identifier]) {
            return plugin;
        }
    }
    return nil;
}

- (BOOL)hasPostProcessPlugins {
    for (SlimPlugin *plugin in self.plugins) {
        if (plugin.type == SLIM_PLUGIN_POST_PROCESS) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)hasCapture {
    return _lastImagePath.length > 0;
}

- (void)noteCaptureWithPath:(NSString *)path
                      width:(int)width
                     height:(int)height
                      scale:(double)scale
                     source:(NSString *)source {
    if (path.length == 0) {
        return;
    }
    _lastImagePath = [path copy];
    _lastWidth = width;
    _lastHeight = height;
    _lastScale = (scale > 0.0) ? scale : 1.0;
    _lastSource = [source copy];
    _lastCaptureDate = [NSDate date];
    slim_log("plugin capture ready: %dx%d source=%s", width, height,
             (_lastSource != nil) ? _lastSource.UTF8String : "");
}

- (NSDictionary *)requestForPlugin:(SlimPlugin *)plugin {
    NSMutableDictionary *request = [NSMutableDictionary dictionary];
    request[@"protocol"] = @1;
    request[@"type"] = [NSString stringWithUTF8String:
        slim_plugin_type_name(plugin.type)];
    request[@"plugin_id"] = plugin.identifier ?: @"";
    request[@"image_path"] = _lastImagePath ?: @"";
    request[@"output_dir"] = NSTemporaryDirectory() ?: @"";
    request[@"width"] = @(_lastWidth);
    request[@"height"] = @(_lastHeight);
    request[@"scale"] = @(_lastScale);
    request[@"source"] = _lastSource ?: @"";
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    request[@"created_at"] = [formatter stringFromDate:
        (_lastCaptureDate != nil) ? _lastCaptureDate : [NSDate date]];
    return request;
}

- (void)runPlugin:(SlimPlugin *)plugin
       completion:(void (^)(BOOL ok, NSString *message))completion {
    if (completion == nil) {
        return;
    }
    if (plugin == nil) {
        completion(NO, NSLocalizedString(@"plugin.error.unknown", nil));
        return;
    }
    if (plugin.type == SLIM_PLUGIN_POST_PROCESS && !self.hasCapture) {
        completion(NO, NSLocalizedString(@"plugin.error.no_capture", nil));
        return;
    }

    NSError *jsonError = nil;
    NSData *requestData =
        [NSJSONSerialization dataWithJSONObject:[self requestForPlugin:plugin]
                                        options:0
                                          error:&jsonError];
    if (requestData == nil) {
        completion(NO, jsonError.localizedDescription ?: NSLocalizedString(@"plugin.error.unknown", nil));
        return;
    }
    NSString *requestString = [[NSString alloc] initWithData:requestData
                                                    encoding:NSUTF8StringEncoding];
    if (requestString.length == 0) {
        completion(NO, NSLocalizedString(@"plugin.error.unknown", nil));
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        slim_plugin_t item;
        memset(&item, 0, sizeof item);
        const char *exec = plugin.execPath.fileSystemRepresentation;
        if (exec != NULL) {
            (void)snprintf(item.exec_path, sizeof item.exec_path, "%s", exec);
        }
        item.timeout_ms = plugin.timeoutMs;

        char *stdout_text = NULL;
        char *stderr_text = NULL;
        char err[256] = { 0 };
        int result = slim_plugin_run(&item, requestString.UTF8String,
                                     &stdout_text, &stderr_text,
                                     err, sizeof err);

        BOOL ok = NO;
        __block NSString *message = nil;
        NSString *clipboardText = nil;
        if (result == 0 && stdout_text != NULL && stdout_text[0] != '\0') {
            NSData *responseData = [NSData dataWithBytes:stdout_text
                                                  length:strlen(stdout_text)];
            NSError *responseError = nil;
            id object = [NSJSONSerialization JSONObjectWithData:responseData
                                                        options:0
                                                          error:&responseError];
            if ([object isKindOfClass:[NSDictionary class]]) {
                NSDictionary *response = object;
                ok = [response[@"ok"] boolValue];
                id value = response[@"message"];
                if ([value isKindOfClass:[NSString class]]) {
                    message = value;
                }
                value = response[@"clipboard_text"];
                if ([value isKindOfClass:[NSString class]]) {
                    clipboardText = value;
                }
                value = response[@"output_path"];
                if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
                    slim_log("plugin %s output: %s",
                             plugin.identifier.UTF8String, [value UTF8String]);
                }
                if (!ok && message.length == 0) {
                    message = NSLocalizedString(@"plugin.error.response", nil);
                }
            } else {
                message = NSLocalizedString(@"plugin.error.response", nil);
            }
        } else if (result == 0) {
            message = NSLocalizedString(@"plugin.error.empty", nil);
        }

        if (!ok) {
            if (err[0] != '\0') {
                message = [NSString stringWithUTF8String:err];
            } else if (stderr_text != NULL && stderr_text[0] != '\0') {
                message = [NSString stringWithUTF8String:stderr_text];
            }
            if (message.length == 0) {
                message = NSLocalizedString(@"plugin.error.unknown", nil);
            }
        }

        free(stdout_text);
        free(stderr_text);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok && clipboardText.length > 0) {
                NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
                [pasteboard clearContents];
                (void)[pasteboard setString:clipboardText
                                    forType:NSPasteboardTypeString];
                slim_log("plugin %s copied %lu chars to clipboard",
                         plugin.identifier.UTF8String,
                         (unsigned long)clipboardText.length);
                message = (message.length > 0)
                              ? [message stringByAppendingFormat:@" · %@",
                                    NSLocalizedString(@"plugin.result.copied", nil)]
                              : NSLocalizedString(@"plugin.result.copied", nil);
            }
            if (ok) {
                if (message.length == 0) {
                    message = NSLocalizedString(@"plugin.result.done", nil);
                }
                slim_log("plugin %s ok: %s", plugin.identifier.UTF8String,
                         message.UTF8String);
            } else {
                slim_log("plugin %s failed: %s", plugin.identifier.UTF8String,
                         message.UTF8String);
            }
            completion(ok, message);
        });
    });
}

@end

void SlimPresentPluginResult(BOOL ok, NSString *pluginName, NSString *message) {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = ok ? NSAlertStyleInformational : NSAlertStyleWarning;
    alert.messageText = (pluginName.length > 0) ? pluginName : @"Slimshot";
    alert.informativeText = (message != nil) ? message : @"";
    [alert addButtonWithTitle:NSLocalizedString(@"alert.ok", nil)];
    [alert runModal];
}
