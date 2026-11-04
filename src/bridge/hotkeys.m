/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#import <dispatch/dispatch.h>

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include "hotkeys.h"
#include "log.h"

static const OSType kSlimHotKeySignature = 'SLIM';

static UInt32 SlimKeyCodeForCharacter(char c) {
    if (c >= 'a' && c <= 'z') {
        c = (char)toupper((unsigned char)c);
    }
    switch (c) {
        case 'A': return kVK_ANSI_A;
        case 'B': return kVK_ANSI_B;
        case 'C': return kVK_ANSI_C;
        case 'D': return kVK_ANSI_D;
        case 'E': return kVK_ANSI_E;
        case 'F': return kVK_ANSI_F;
        case 'G': return kVK_ANSI_G;
        case 'H': return kVK_ANSI_H;
        case 'I': return kVK_ANSI_I;
        case 'J': return kVK_ANSI_J;
        case 'K': return kVK_ANSI_K;
        case 'L': return kVK_ANSI_L;
        case 'M': return kVK_ANSI_M;
        case 'N': return kVK_ANSI_N;
        case 'O': return kVK_ANSI_O;
        case 'P': return kVK_ANSI_P;
        case 'Q': return kVK_ANSI_Q;
        case 'R': return kVK_ANSI_R;
        case 'S': return kVK_ANSI_S;
        case 'T': return kVK_ANSI_T;
        case 'U': return kVK_ANSI_U;
        case 'V': return kVK_ANSI_V;
        case 'W': return kVK_ANSI_W;
        case 'X': return kVK_ANSI_X;
        case 'Y': return kVK_ANSI_Y;
        case 'Z': return kVK_ANSI_Z;
        case '0': return kVK_ANSI_0;
        case '1': return kVK_ANSI_1;
        case '2': return kVK_ANSI_2;
        case '3': return kVK_ANSI_3;
        case '4': return kVK_ANSI_4;
        case '5': return kVK_ANSI_5;
        case '6': return kVK_ANSI_6;
        case '7': return kVK_ANSI_7;
        case '8': return kVK_ANSI_8;
        case '9': return kVK_ANSI_9;
        case '-': return kVK_ANSI_Minus;
        case '=': return kVK_ANSI_Equal;
        case '[': return kVK_ANSI_LeftBracket;
        case ']': return kVK_ANSI_RightBracket;
        case ';': return kVK_ANSI_Semicolon;
        case '\'': return kVK_ANSI_Quote;
        case ',': return kVK_ANSI_Comma;
        case '.': return kVK_ANSI_Period;
        case '/': return kVK_ANSI_Slash;
        case '\\': return kVK_ANSI_Backslash;
        case '`': return kVK_ANSI_Grave;
        default: return UINT32_MAX;
    }
}

static UInt32 SlimKeyCodeForFunctionKey(const char *token) {
    static const UInt32 functionKeys[] = {
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
    };
    if ((token[0] != 'f' && token[0] != 'F') || token[1] == '\0') {
        return UINT32_MAX;
    }
    char *end = NULL;
    long number = strtol(token + 1, &end, 10);
    if (end == NULL || *end != '\0' || number < 1 || number > 12) {
        return UINT32_MAX;
    }
    return functionKeys[number - 1];
}

static BOOL SlimParseHotKey(NSString *specification, UInt32 *outKeyCode,
                            UInt32 *outModifiers, NSString **error) {
    *outKeyCode = UINT32_MAX;
    *outModifiers = 0;

    char buffer[128];
    if (![specification getCString:buffer
                         maxLength:sizeof buffer
                          encoding:NSUTF8StringEncoding]) {
        if (error != NULL) {
            *error = @"Hotkey string is too long or not valid UTF-8.";
        }
        return NO;
    }

    UInt32 modifiers = 0;
    char keyToken[64] = { 0 };
    BOOL foundKey = NO;

    char *save = NULL;
    char *token = strtok_r(buffer, "+", &save);
    while (token != NULL) {
        while (*token == ' ' || *token == '\t') {
            token++;
        }
        char *end = token + strlen(token);
        while (end > token && (end[-1] == ' ' || end[-1] == '\t')) {
            *--end = '\0';
        }
        if (*token == '\0') {
            token = strtok_r(NULL, "+", &save);
            continue;
        }

        char *next = strtok_r(NULL, "+", &save);
        if (next == NULL) {
            (void)snprintf(keyToken, sizeof keyToken, "%s", token);
            foundKey = YES;
            break;
        }

        if (strcasecmp(token, "cmd") == 0 || strcasecmp(token, "command") == 0) {
            modifiers |= cmdKey;
        } else if (strcasecmp(token, "shift") == 0) {
            modifiers |= shiftKey;
        } else if (strcasecmp(token, "alt") == 0 ||
                   strcasecmp(token, "option") == 0 ||
                   strcasecmp(token, "opt") == 0) {
            modifiers |= optionKey;
        } else if (strcasecmp(token, "ctrl") == 0 ||
                   strcasecmp(token, "control") == 0) {
            modifiers |= controlKey;
        } else {
            if (error != NULL) {
                *error = [NSString stringWithFormat:@"Unknown modifier: %s", token];
            }
            return NO;
        }
        token = next;
    }

    if (!foundKey || keyToken[0] == '\0') {
        if (error != NULL) {
            *error = @"Hotkey is missing a key.";
        }
        return NO;
    }
    if (modifiers == 0) {
        if (error != NULL) {
            *error = @"Hotkey needs at least one modifier.";
        }
        return NO;
    }

    UInt32 keyCode = UINT32_MAX;
    if (strlen(keyToken) == 1) {
        keyCode = SlimKeyCodeForCharacter(keyToken[0]);
    } else if (strcasecmp(keyToken, "space") == 0) {
        keyCode = kVK_Space;
    } else if (strcasecmp(keyToken, "return") == 0 ||
               strcasecmp(keyToken, "enter") == 0) {
        keyCode = kVK_Return;
    } else if (strcasecmp(keyToken, "escape") == 0 ||
               strcasecmp(keyToken, "esc") == 0) {
        keyCode = kVK_Escape;
    } else if (strcasecmp(keyToken, "tab") == 0) {
        keyCode = kVK_Tab;
    } else if (strcasecmp(keyToken, "delete") == 0 ||
               strcasecmp(keyToken, "backspace") == 0) {
        keyCode = kVK_Delete;
    } else {
        keyCode = SlimKeyCodeForFunctionKey(keyToken);
    }

    if (keyCode == UINT32_MAX) {
        if (error != NULL) {
            *error = [NSString stringWithFormat:@"Unknown key: %s", keyToken];
        }
        return NO;
    }

    *outKeyCode = keyCode;
    *outModifiers = modifiers;
    return YES;
}

@interface SlimHotKeyManager ()
- (void)handleHotKeyID:(UInt32)hotKeyID;
@end

static OSStatus SlimHotKeyEventHandler(EventHandlerCallRef nextHandler,
                                       EventRef event, void *userData) {
    (void)nextHandler;
    SlimHotKeyManager *manager = (__bridge SlimHotKeyManager *)userData;

    EventHotKeyID hotKeyID;
    OSStatus status = GetEventParameter(event, kEventParamDirectObject,
                                        typeEventHotKeyID, NULL,
                                        sizeof hotKeyID, NULL, &hotKeyID);
    if (status == noErr && hotKeyID.signature == kSlimHotKeySignature) {
        [manager handleHotKeyID:hotKeyID.id];
    }
    return noErr;
}

@implementation SlimHotKeyManager {
    void (^_handler)(SlimCaptureMode);
    EventHandlerRef _eventHandler;
    EventHotKeyRef _hotKeyRefs[3];
}

- (instancetype)initWithHandler:(void (^)(SlimCaptureMode mode))handler {
    self = [super init];
    if (self != nil) {
        _handler = [handler copy];
        EventTypeSpec eventType = { kEventClassKeyboard, kEventHotKeyPressed };
        OSStatus status = InstallEventHandler(GetApplicationEventTarget(),
                                              SlimHotKeyEventHandler, 1,
                                              &eventType, (__bridge void *)self,
                                              &_eventHandler);
        if (status != noErr) {
            slim_log("hotkey event handler install failed: %d", (int)status);
        }
    }
    return self;
}

- (void)dealloc {
    [self unregisterAll];
    if (_eventHandler != NULL) {
        (void)RemoveEventHandler(_eventHandler);
        _eventHandler = NULL;
    }
}

- (BOOL)registerHotKey:(NSString *)specification
                  mode:(SlimCaptureMode)mode
                 error:(NSString **)error {
    UInt32 keyCode = UINT32_MAX;
    UInt32 modifiers = 0;
    if (!SlimParseHotKey(specification, &keyCode, &modifiers, error)) {
        return NO;
    }

    NSInteger index = (NSInteger)mode;
    if (index < 0 || index >= 3) {
        if (error != NULL) {
            *error = @"Invalid capture mode.";
        }
        return NO;
    }

    if (_hotKeyRefs[index] != NULL) {
        (void)UnregisterEventHotKey(_hotKeyRefs[index]);
        _hotKeyRefs[index] = NULL;
    }

    EventHotKeyID hotKeyID;
    hotKeyID.signature = kSlimHotKeySignature;
    hotKeyID.id = (UInt32)(index + 1);

    OSStatus status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                          GetApplicationEventTarget(), 0,
                                          &_hotKeyRefs[index]);
    if (status != noErr) {
        if (error != NULL) {
            *error = [NSString stringWithFormat:@"RegisterEventHotKey failed: %d",
                                                (int)status];
        }
        return NO;
    }
    return YES;
}

- (void)unregisterAll {
    for (NSInteger i = 0; i < 3; i++) {
        if (_hotKeyRefs[i] != NULL) {
            (void)UnregisterEventHotKey(_hotKeyRefs[i]);
            _hotKeyRefs[i] = NULL;
        }
    }
}

- (void)handleHotKeyID:(UInt32)hotKeyID {
    NSInteger index = (NSInteger)hotKeyID - 1;
    if (index < 0 || index >= 3 || _handler == nil) {
        return;
    }
    SlimCaptureMode mode = (SlimCaptureMode)index;
    void (^handler)(SlimCaptureMode) = _handler;
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(mode);
    });
}

@end
