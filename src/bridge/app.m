/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>

#include <stdlib.h>
#include <string.h>

#include "app.h"
#include "capture.h"
#include "config.h"
#include "hotkeys.h"
#include "log.h"
#include "permissions.h"
#include "settings.h"

@implementation AppDelegate {
    slim_config_t _config;
    NSStatusItem *_statusItem;
    NSMenuItem *_permissionStatusItem;
    SettingsWindowController *_settingsController;
    SlimCaptureController *_captureController;
    SlimHotKeyManager *_hotKeyManager;
    CGDirectDisplayID _preferredDisplayID;
    BOOL _hasPreferredDisplay;
    NSMenu *_displayMenu;
    BOOL _permissionAlertShown;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    slim_log_init();
    slim_log("Slimshot starting");

    char err[256] = { 0 };
    if (slim_config_load(&_config, err, sizeof err) != 0) {
        slim_log("config load failed, using defaults: %s", err);
    }

    __weak AppDelegate *weakSelf = self;
    _hotKeyManager = [[SlimHotKeyManager alloc] initWithHandler:^(SlimCaptureMode mode) {
        [weakSelf beginCaptureMode:mode];
    }];
    [self registerConfiguredHotKeys];

    [self setupStatusItem];
    [self setupMenu];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenParametersDidChange:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];
    [self refreshPermissionStatus];
    slim_log("screen recording authorized: %s",
             slim_screen_capture_authorized() ? "yes" : "no");

    if (getenv("SLIMSHOT_OPEN_SETTINGS") != NULL) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self showSettings:nil];
        });
    }

    const char *captureOnLaunch = getenv("SLIMSHOT_CAPTURE_ON_LAUNCH");
    if (captureOnLaunch != NULL) {
        SlimCaptureMode mode = SlimCaptureModeFullScreen;
        if (strcmp(captureOnLaunch, "region") == 0) {
            mode = SlimCaptureModeRegion;
        } else if (strcmp(captureOnLaunch, "window") == 0) {
            mode = SlimCaptureModeWindow;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self beginCaptureMode:mode];
        });
    }

    if (getenv("SLIMSHOT_SKIP_PERMISSION_PROMPT") == NULL &&
        !slim_screen_capture_authorized()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!self->_permissionAlertShown) {
                self->_permissionAlertShown = YES;
                [self showPermissionAlert];
            }
        });
    }
}

- (void)registerHotKeySpec:(const char *)spec
                      mode:(SlimCaptureMode)mode
                      name:(NSString *)name {
    if (spec == NULL || spec[0] == '\0') {
        slim_log("hotkey %s is empty", name.UTF8String);
        return;
    }
    NSString *specString = [NSString stringWithUTF8String:spec];
    NSString *error = nil;
    if ([_hotKeyManager registerHotKey:specString mode:mode error:&error]) {
        slim_log("hotkey %s registered: %s", name.UTF8String, spec);
    } else {
        const char *message = error.UTF8String;
        slim_log("hotkey %s failed (%s): %s", name.UTF8String, spec,
                 message != NULL ? message : "");
    }
}

- (void)registerConfiguredHotKeys {
    [self registerHotKeySpec:_config.hotkey_fullscreen
                        mode:SlimCaptureModeFullScreen
                        name:@"full screen"];
    [self registerHotKeySpec:_config.hotkey_window
                        mode:SlimCaptureModeWindow
                        name:@"window"];
    [self registerHotKeySpec:_config.hotkey_region
                        mode:SlimCaptureModeRegion
                        name:@"region"];
}

- (void)setupStatusItem {
    _statusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];
    NSImage *icon = [NSImage imageWithSystemSymbolName:@"camera.viewfinder"
                              accessibilityDescription:@"Slimshot"];
    if (icon != nil) {
        icon.template = YES;
        _statusItem.button.image = icon;
    } else {
        _statusItem.button.title = @"Slimshot";
    }
    _statusItem.button.toolTip = @"Slimshot";
}

- (void)addCaptureItemToMenu:(NSMenu *)menu
                    titleKey:(NSString *)titleKey
                      action:(SEL)action
                 keyEquiv:(NSString *)keyEquiv
                      mask:(NSEventModifierFlags)mask {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(titleKey, nil)
                                                  action:action
                                           keyEquivalent:keyEquiv];
    item.keyEquivalentModifierMask = mask;
    item.target = self;
    [menu addItem:item];
}

- (void)addDisplayMenuItemToMenu:(NSMenu *)menu {
    NSString *title = NSLocalizedString(@"menu.display", nil);
    NSMenuItem *displayItem = [[NSMenuItem alloc] initWithTitle:title
                                                         action:NULL
                                                  keyEquivalent:@""];
    _displayMenu = [[NSMenu alloc] initWithTitle:title];
    _displayMenu.delegate = self;
    displayItem.submenu = _displayMenu;
    [menu addItem:displayItem];
    [self rebuildDisplayMenu];
}

- (NSScreen *)screenForDisplayID:(CGDirectDisplayID)displayID {
    for (NSScreen *screen in [NSScreen screens]) {
        NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
        if (screenNumber != nil &&
            (CGDirectDisplayID)screenNumber.unsignedIntValue == displayID) {
            return screen;
        }
    }
    return nil;
}

- (void)rebuildDisplayMenu {
    if (_displayMenu == nil) {
        return;
    }
    [_displayMenu removeAllItems];

    NSMenuItem *currentItem =
        [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.display.current", nil)
                                   action:@selector(selectCaptureScreen:)
                            keyEquivalent:@""];
    currentItem.target = self;
    currentItem.tag = 0;
    currentItem.state = _hasPreferredDisplay ? NSControlStateValueOff : NSControlStateValueOn;
    [_displayMenu addItem:currentItem];

    BOOL preferredFound = NO;
    for (NSScreen *screen in [NSScreen screens]) {
        NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
        if (screenNumber == nil) {
            continue;
        }
        CGDirectDisplayID displayID = (CGDirectDisplayID)screenNumber.unsignedIntValue;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:screen.localizedName
                                                      action:@selector(selectCaptureScreen:)
                                               keyEquivalent:@""];
        item.target = self;
        item.tag = 1;
        item.representedObject = @(displayID);
        if (_hasPreferredDisplay && displayID == _preferredDisplayID) {
            item.state = NSControlStateValueOn;
            preferredFound = YES;
        }
        [_displayMenu addItem:item];
    }

    if (_hasPreferredDisplay && !preferredFound) {
        slim_log("preferred display %u disconnected; following cursor",
                 _preferredDisplayID);
        _hasPreferredDisplay = NO;
        currentItem.state = NSControlStateValueOn;
    }
}

- (void)selectCaptureScreen:(NSMenuItem *)sender {
    if (sender.tag == 0) {
        _hasPreferredDisplay = NO;
        slim_log("capture display: following cursor");
    } else {
        NSNumber *screenNumber = sender.representedObject;
        _preferredDisplayID = (CGDirectDisplayID)screenNumber.unsignedIntValue;
        _hasPreferredDisplay = YES;
        slim_log("capture display selected: %u", _preferredDisplayID);
    }

    for (NSMenuItem *item in _displayMenu.itemArray) {
        item.state = NSControlStateValueOff;
    }
    sender.state = NSControlStateValueOn;
}

- (void)screenParametersDidChange:(NSNotification *)notification {
    (void)notification;
    slim_log("screen parameters changed: %lu screens",
             (unsigned long)[NSScreen screens].count);
    if (_hasPreferredDisplay && [self screenForDisplayID:_preferredDisplayID] == nil) {
        slim_log("preferred display %u disconnected; following cursor",
                 _preferredDisplayID);
        _hasPreferredDisplay = NO;
    }
    [self rebuildDisplayMenu];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu == _displayMenu) {
        [self rebuildDisplayMenu];
    } else {
        [self refreshPermissionStatus];
    }
}

- (void)setupMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Slimshot"];
    menu.delegate = self;

    [self addCaptureItemToMenu:menu
                      titleKey:@"menu.capture.full"
                        action:@selector(captureFullScreen:)
                    keyEquiv:@"1"
                          mask:(NSEventModifierFlagOption | NSEventModifierFlagShift)];
    [self addCaptureItemToMenu:menu
                      titleKey:@"menu.capture.window"
                        action:@selector(captureWindow:)
                    keyEquiv:@"2"
                          mask:(NSEventModifierFlagOption | NSEventModifierFlagShift)];
    [self addCaptureItemToMenu:menu
                      titleKey:@"menu.capture.region"
                        action:@selector(captureRegion:)
                    keyEquiv:@"a"
                          mask:(NSEventModifierFlagCommand | NSEventModifierFlagShift)];

    [menu addItem:[NSMenuItem separatorItem]];
    [self addDisplayMenuItemToMenu:menu];
    [menu addItem:[NSMenuItem separatorItem]];

    _permissionStatusItem = [[NSMenuItem alloc] initWithTitle:@""
                                                       action:NULL
                                                keyEquivalent:@""];
    _permissionStatusItem.enabled = NO;
    [menu addItem:_permissionStatusItem];

    NSMenuItem *permissionItem =
        [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.permission", nil)
                                   action:@selector(showPermission:)
                            keyEquivalent:@""];
    permissionItem.target = self;
    [menu addItem:permissionItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *settingsItem =
        [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.settings", nil)
                                   action:@selector(showSettings:)
                            keyEquivalent:@","];
    settingsItem.target = self;
    [menu addItem:settingsItem];

    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.about", nil)
                                                       action:@selector(showAbout:)
                                                keyEquivalent:@""];
    aboutItem.target = self;
    [menu addItem:aboutItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"menu.quit", nil)
                                                      action:@selector(quitApp:)
                                               keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];

    _statusItem.menu = menu;
}

- (void)refreshPermissionStatus {
    BOOL granted = slim_screen_capture_authorized();
    _permissionStatusItem.title = NSLocalizedString(
        granted ? @"menu.permission.status.granted" : @"menu.permission.status.denied", nil);
}

- (void)showPermissionAlert {
    [NSApp activateIgnoringOtherApps:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = NSLocalizedString(@"alert.permission.title", nil);
    alert.informativeText = NSLocalizedString(@"alert.permission.body", nil);
    [alert addButtonWithTitle:NSLocalizedString(@"alert.permission.open", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"alert.permission.request", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"alert.permission.later", nil)];

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        slim_open_screen_capture_settings();
    } else if (response == NSAlertSecondButtonReturn) {
        (void)slim_request_screen_capture();
    }
    [self refreshPermissionStatus];
}

- (void)showPermission:(id)sender {
    (void)sender;

    if (slim_screen_capture_authorized()) {
        [NSApp activateIgnoringOtherApps:YES];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"alert.permission.granted.title", nil);
        alert.informativeText = NSLocalizedString(@"alert.permission.granted.body", nil);
        [alert addButtonWithTitle:NSLocalizedString(@"alert.ok", nil)];
        [alert runModal];
    } else {
        [self showPermissionAlert];
    }
    [self refreshPermissionStatus];
}

- (void)beginCaptureMode:(SlimCaptureMode)mode {
    if (!slim_screen_capture_authorized()) {
        [self showPermissionAlert];
        return;
    }

    NSScreen *preferredScreen = nil;
    if (_hasPreferredDisplay) {
        preferredScreen = [self screenForDisplayID:_preferredDisplayID];
        if (preferredScreen == nil) {
            slim_log("preferred display %u not found; following cursor",
                     _preferredDisplayID);
            _hasPreferredDisplay = NO;
        }
    }

    if (_captureController == nil) {
        _captureController = [[SlimCaptureController alloc] initWithConfig:&_config];
    }
    [_captureController captureMode:mode onScreen:preferredScreen];
}

- (void)captureFullScreen:(id)sender {
    (void)sender;
    [self beginCaptureMode:SlimCaptureModeFullScreen];
}

- (void)captureWindow:(id)sender {
    (void)sender;
    [self beginCaptureMode:SlimCaptureModeWindow];
}

- (void)captureRegion:(id)sender {
    (void)sender;
    [self beginCaptureMode:SlimCaptureModeRegion];
}

- (void)showSettings:(id)sender {
    (void)sender;
    if (_settingsController == nil) {
        _settingsController = [[SettingsWindowController alloc] initWithConfig:&_config];
    }
    [_settingsController present];
}

- (void)showAbout:(id)sender {
    (void)sender;
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanel:nil];
}

- (void)quitApp:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_hotKeyManager unregisterAll];
    slim_log("Slimshot exiting");
    slim_log_close();
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return NO;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    (void)app;
    return YES;
}

@end
