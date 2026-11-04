/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>

#include "about.h"

@implementation SlimAboutWindowController

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 380, 420)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = NSLocalizedString(@"menu.about", nil);
    [window setReleasedWhenClosed:NO];

    self = [super initWithWindow:window];
    if (self != nil) {
        [self buildUI];
        [window center];
    }
    return self;
}

- (NSString *)versionString {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    if (version.length == 0) {
        version = @"0.1.0";
    }
    if (build.length == 0) {
        build = @"1";
    }
    return [NSString stringWithFormat:NSLocalizedString(@"about.version", nil),
                                      version, build];
}

- (void)buildUI {
    NSView *content = self.window.contentView;
    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 8.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:content.leadingAnchor
                                                          constant:24.0],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor
                                                         constant:-24.0],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:28.0],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor
                                                       constant:-24.0],
    ]];

    NSImage *icon = nil;
    NSURL *iconURL = [[NSBundle mainBundle] URLForResource:@"Slimshot"
                                               withExtension:@"icns"];
    if (iconURL != nil) {
        icon = [[NSImage alloc] initWithContentsOfURL:iconURL];
    }
    if (icon == nil) {
        icon = [NSImage imageNamed:NSImageNameApplicationIcon];
    }
    NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 128, 128)];
    iconView.image = icon;
    iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [iconView.widthAnchor constraintEqualToConstant:128.0].active = YES;
    [iconView.heightAnchor constraintEqualToConstant:128.0].active = YES;
    [stack addArrangedSubview:iconView];

    NSTextField *title = [NSTextField labelWithString:@"Slimshot"];
    title.font = [NSFont systemFontOfSize:26.0 weight:NSFontWeightSemibold];
    title.alignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:title];

    NSTextField *version = [NSTextField labelWithString:[self versionString]];
    version.font = [NSFont systemFontOfSize:12.0];
    version.textColor = [NSColor secondaryLabelColor];
    version.alignment = NSTextAlignmentCenter;
    [stack addArrangedSubview:version];

    NSTextField *tagline =
        [NSTextField wrappingLabelWithString:NSLocalizedString(@"about.tagline", nil)];
    tagline.font = [NSFont systemFontOfSize:13.0];
    tagline.alignment = NSTextAlignmentCenter;
    tagline.maximumNumberOfLines = 2;
    [tagline.widthAnchor constraintLessThanOrEqualToConstant:320.0].active = YES;
    [stack addArrangedSubview:tagline];
    [stack setCustomSpacing:14.0 afterView:tagline];

    NSButton *copyButton =
        [NSButton buttonWithTitle:NSLocalizedString(@"about.copy_version", nil)
                           target:self
                           action:@selector(copyVersionInfo:)];
    NSButton *licenseButton =
        [NSButton buttonWithTitle:NSLocalizedString(@"about.license", nil)
                           target:self
                           action:@selector(openLicense:)];
    NSButton *closeButton = [NSButton buttonWithTitle:NSLocalizedString(@"about.close", nil)
                                               target:self
                                               action:@selector(closeAbout:)];
    closeButton.keyEquivalent = @"\r";
    NSStackView *buttons =
        [NSStackView stackViewWithViews:@[ copyButton, licenseButton, closeButton ]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.alignment = NSLayoutAttributeCenterY;
    buttons.spacing = 8.0;
    [stack addArrangedSubview:buttons];

    NSString *copyright =
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSHumanReadableCopyright"];
    if (copyright.length > 0) {
        NSTextField *copyrightLabel = [NSTextField wrappingLabelWithString:copyright];
        copyrightLabel.font = [NSFont systemFontOfSize:10.0];
        copyrightLabel.textColor = [NSColor tertiaryLabelColor];
        copyrightLabel.alignment = NSTextAlignmentCenter;
        copyrightLabel.maximumNumberOfLines = 2;
        [copyrightLabel.widthAnchor constraintLessThanOrEqualToConstant:320.0].active = YES;
        [stack setCustomSpacing:16.0 afterView:buttons];
        [stack addArrangedSubview:copyrightLabel];
    }

    [stack layoutSubtreeIfNeeded];
    NSSize fitting = stack.fittingSize;
    CGFloat height = MAX(360.0, fitting.height + 52.0);
    [self.window setContentSize:NSMakeSize(380.0, height)];
}

- (void)copyVersionInfo:(id)sender {
    (void)sender;
    NSString *info = [NSString stringWithFormat:@"Slimshot\n%@\nmacOS %@",
                                                [self versionString],
                                                NSProcessInfo.processInfo.operatingSystemVersionString];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:info forType:NSPasteboardTypeString];
}

- (void)openLicense:(id)sender {
    (void)sender;
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"LICENSE" withExtension:nil];
    if (url == nil) {
        NSBeep();
        return;
    }
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)closeAbout:(id)sender {
    (void)sender;
    [self.window close];
}

- (void)present {
    [NSApp activateIgnoringOtherApps:YES];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
}

@end
