/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>

#include <math.h>
#include <stdio.h>

#include "config.h"
#include "paths.h"
#include "permissions.h"
#include "settings.h"

@implementation SettingsWindowController {
    slim_config_t *_config;
    NSButton *_includeCursorCheck;
    NSButton *_copyCheck;
    NSButton *_autoSaveCheck;
    NSButton *_thumbnailCheck;
    NSStepper *_thumbnailStepper;
    NSTextField *_thumbnailSecondsLabel;
    NSPopUpButton *_formatPopup;
    NSSlider *_jpegSlider;
    NSTextField *_jpegValueLabel;
    NSSlider *_heicSlider;
    NSTextField *_heicValueLabel;
    NSTextField *_folderLabel;
    NSTextField *_permissionStatusLabel;
}

- (instancetype)initWithConfig:(slim_config_t *)config {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 520, 540)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = NSLocalizedString(@"settings.title", nil);
    [window setReleasedWhenClosed:NO];

    self = [super initWithWindow:window];
    if (self != nil) {
        _config = config;
        [self buildUI];
        [self refreshControls];
        [window center];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:NSApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSTextField *)sectionLabel:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont boldSystemFontOfSize:13.0];
    return label;
}

- (NSStackView *)rowWithLabel:(NSString *)text control:(NSView *)control {
    NSTextField *label = [NSTextField labelWithString:text];
    NSStackView *row = [NSStackView stackViewWithViews:@[ label, control ]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8.0;
    return row;
}

- (NSStackView *)qualityRowWithTitle:(NSString *)title
                              slider:(NSSlider *)slider
                          valueLabel:(NSTextField *)valueLabel {
    NSTextField *label = [NSTextField labelWithString:title];
    [label.widthAnchor constraintEqualToConstant:90.0].active = YES;
    NSStackView *row = [NSStackView stackViewWithViews:@[ label, slider, valueLabel ]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8.0;
    return row;
}

- (void)buildUI {
    NSView *content = self.window.contentView;
    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20.0],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20.0],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:20.0],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-20.0],
    ]];

    [stack addArrangedSubview:[self sectionLabel:NSLocalizedString(@"settings.capture_options", nil)]];

    _includeCursorCheck = [NSButton checkboxWithTitle:NSLocalizedString(@"settings.include_cursor", nil)
                                               target:self
                                               action:@selector(toggleIncludeCursor:)];
    [stack addArrangedSubview:_includeCursorCheck];

    NSBox *captureSeparator = [[NSBox alloc] init];
    captureSeparator.boxType = NSBoxSeparator;
    [stack addArrangedSubview:captureSeparator];
    [captureSeparator.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;

    [stack addArrangedSubview:[self sectionLabel:NSLocalizedString(@"settings.capture", nil)]];

    _copyCheck = [NSButton checkboxWithTitle:NSLocalizedString(@"settings.copy", nil)
                                      target:self
                                      action:@selector(toggleCopy:)];
    [stack addArrangedSubview:_copyCheck];

    _autoSaveCheck = [NSButton checkboxWithTitle:NSLocalizedString(@"settings.auto_save", nil)
                                          target:self
                                          action:@selector(toggleAutoSave:)];
    [stack addArrangedSubview:_autoSaveCheck];

    _thumbnailCheck = [NSButton checkboxWithTitle:NSLocalizedString(@"settings.thumbnail", nil)
                                           target:self
                                           action:@selector(toggleThumbnail:)];
    [stack addArrangedSubview:_thumbnailCheck];

    _thumbnailSecondsLabel = [NSTextField labelWithString:@""];
    _thumbnailStepper = [[NSStepper alloc] init];
    _thumbnailStepper.minValue = 0;
    _thumbnailStepper.maxValue = 60;
    _thumbnailStepper.increment = 1;
    _thumbnailStepper.target = self;
    _thumbnailStepper.action = @selector(thumbnailSecondsChanged:);
    NSStackView *secondsRow =
        [NSStackView stackViewWithViews:@[ _thumbnailSecondsLabel, _thumbnailStepper ]];
    secondsRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    secondsRow.alignment = NSLayoutAttributeCenterY;
    secondsRow.spacing = 8.0;
    secondsRow.edgeInsets = NSEdgeInsetsMake(0.0, 20.0, 0.0, 0.0);
    [stack addArrangedSubview:secondsRow];

    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    [stack addArrangedSubview:separator];
    [separator.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;

    [stack addArrangedSubview:[self sectionLabel:NSLocalizedString(@"settings.output", nil)]];

    _formatPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_formatPopup addItemsWithTitles:@[ @"PNG", @"JPEG", @"HEIC", @"TIFF" ]];
    _formatPopup.target = self;
    _formatPopup.action = @selector(formatChanged:);
    [stack addArrangedSubview:[self rowWithLabel:NSLocalizedString(@"settings.format", nil)
                                         control:_formatPopup]];

    _jpegSlider = [NSSlider sliderWithValue:_config->jpeg_quality
                                   minValue:1.0
                                   maxValue:100.0
                                     target:self
                                     action:@selector(jpegQualityChanged:)];
    _jpegSlider.continuous = NO;
    [_jpegSlider.widthAnchor constraintEqualToConstant:180.0].active = YES;
    _jpegValueLabel = [NSTextField labelWithString:@""];
    _jpegValueLabel.alignment = NSTextAlignmentRight;
    [_jpegValueLabel.widthAnchor constraintEqualToConstant:32.0].active = YES;
    [stack addArrangedSubview:[self qualityRowWithTitle:NSLocalizedString(@"settings.quality.jpeg", nil)
                                                slider:_jpegSlider
                                            valueLabel:_jpegValueLabel]];

    _heicSlider = [NSSlider sliderWithValue:_config->heic_quality
                                   minValue:1.0
                                   maxValue:100.0
                                     target:self
                                     action:@selector(heicQualityChanged:)];
    _heicSlider.continuous = NO;
    [_heicSlider.widthAnchor constraintEqualToConstant:180.0].active = YES;
    _heicValueLabel = [NSTextField labelWithString:@""];
    _heicValueLabel.alignment = NSTextAlignmentRight;
    [_heicValueLabel.widthAnchor constraintEqualToConstant:32.0].active = YES;
    [stack addArrangedSubview:[self qualityRowWithTitle:NSLocalizedString(@"settings.quality.heic", nil)
                                                slider:_heicSlider
                                            valueLabel:_heicValueLabel]];

    _folderLabel = [NSTextField labelWithString:@""];
    _folderLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _folderLabel.maximumNumberOfLines = 1;
    [_folderLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_folderLabel.widthAnchor constraintGreaterThanOrEqualToConstant:340.0].active = YES;

    NSButton *chooseButton = [NSButton buttonWithTitle:NSLocalizedString(@"settings.choose", nil)
                                                target:self
                                                action:@selector(chooseFolder:)];
    NSStackView *folderRow = [NSStackView stackViewWithViews:@[ _folderLabel, chooseButton ]];
    folderRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    folderRow.alignment = NSLayoutAttributeCenterY;
    folderRow.spacing = 8.0;
    [stack addArrangedSubview:folderRow];

    NSBox *permissionSeparator = [[NSBox alloc] init];
    permissionSeparator.boxType = NSBoxSeparator;
    [stack addArrangedSubview:permissionSeparator];
    [permissionSeparator.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;

    [stack addArrangedSubview:[self sectionLabel:NSLocalizedString(@"settings.permission.section", nil)]];

    _permissionStatusLabel = [NSTextField labelWithString:@""];
    _permissionStatusLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];

    NSButton *permissionButton =
        [NSButton buttonWithTitle:NSLocalizedString(@"settings.permission", nil)
                           target:self
                           action:@selector(openPermissionSettings:)];
    NSStackView *permissionRow =
        [NSStackView stackViewWithViews:@[ _permissionStatusLabel, permissionButton ]];
    permissionRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    permissionRow.alignment = NSLayoutAttributeCenterY;
    permissionRow.spacing = 12.0;
    [stack addArrangedSubview:permissionRow];

    NSTextField *permissionHint =
        [NSTextField labelWithString:NSLocalizedString(@"settings.permission.restart", nil)];
    permissionHint.font = [NSFont systemFontOfSize:11.0];
    permissionHint.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:permissionHint];

    NSButton *openConfigButton =
        [NSButton buttonWithTitle:NSLocalizedString(@"settings.open_config", nil)
                           target:self
                           action:@selector(openConfigFolder:)];
    NSButton *closeButton = [NSButton buttonWithTitle:NSLocalizedString(@"settings.close", nil)
                                               target:self
                                               action:@selector(closeWindow:)];
    NSStackView *buttonRow =
        [NSStackView stackViewWithViews:@[ openConfigButton, closeButton ]];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.alignment = NSLayoutAttributeCenterY;
    buttonRow.spacing = 8.0;
    [stack addArrangedSubview:buttonRow];

    char configPath[SLIM_PATH_MAX];
    if (slim_paths_config(configPath, sizeof configPath) == 0) {
        NSTextField *pathLabel = [NSTextField labelWithString:
            [NSString stringWithFormat:@"config: %s", configPath]];
        pathLabel.font = [NSFont monospacedSystemFontOfSize:10.0 weight:NSFontWeightRegular];
        pathLabel.textColor = [NSColor secondaryLabelColor];
        [stack addArrangedSubview:pathLabel];
    }
}

- (void)refreshControls {
    _includeCursorCheck.state =
        _config->include_cursor ? NSControlStateValueOn : NSControlStateValueOff;
    _copyCheck.state =
        _config->copy_to_clipboard ? NSControlStateValueOn : NSControlStateValueOff;
    _autoSaveCheck.state = _config->auto_save ? NSControlStateValueOn : NSControlStateValueOff;
    _thumbnailCheck.state =
        _config->show_thumbnail ? NSControlStateValueOn : NSControlStateValueOff;

    _thumbnailStepper.integerValue = _config->thumbnail_seconds;
    [self updateThumbnailSecondsLabel];

    _jpegSlider.doubleValue = _config->jpeg_quality;
    _heicSlider.doubleValue = _config->heic_quality;
    [self updateQualityLabels];

    NSArray<NSString *> *values = @[ @"png", @"jpeg", @"heic", @"tiff" ];
    NSString *format = [NSString stringWithUTF8String:_config->format];
    NSUInteger index = [values indexOfObject:format];
    [_formatPopup selectItemAtIndex:(index == NSNotFound) ? 0 : (NSInteger)index];

    [self updateFolderLabel];
    [self refreshPermissionStatus];
}

- (void)updateThumbnailSecondsLabel {
    _thumbnailSecondsLabel.stringValue = [NSString stringWithFormat:
        NSLocalizedString(@"settings.thumbnail_seconds", nil), _config->thumbnail_seconds];
}

- (void)updateQualityLabels {
    _jpegValueLabel.stringValue = [NSString stringWithFormat:@"%d", _config->jpeg_quality];
    _heicValueLabel.stringValue = [NSString stringWithFormat:@"%d", _config->heic_quality];
}

- (void)refreshPermissionStatus {
    BOOL granted = slim_screen_capture_authorized();
    _permissionStatusLabel.stringValue = NSLocalizedString(
        granted ? @"settings.permission.status.granted"
                : @"settings.permission.status.denied", nil);
    _permissionStatusLabel.textColor =
        granted ? [NSColor systemGreenColor] : [NSColor systemOrangeColor];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    if (self.window.isVisible) {
        [self refreshPermissionStatus];
    }
}

- (void)updateFolderLabel {
    NSString *path = [NSString stringWithUTF8String:_config->save_directory];
    if (path == nil) {
        path = @"";
    }
    _folderLabel.stringValue =
        [NSString stringWithFormat:NSLocalizedString(@"settings.folder", nil), path];
    _folderLabel.toolTip = path;
}

- (void)saveConfig {
    char err[256] = { 0 };
    if (slim_config_save(_config, err, sizeof err) != 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = NSLocalizedString(@"alert.save_failed.title", nil);
        alert.informativeText = [NSString stringWithUTF8String:err];
        [alert addButtonWithTitle:NSLocalizedString(@"alert.ok", nil)];
        [alert runModal];
    }
}

- (void)toggleIncludeCursor:(NSButton *)sender {
    _config->include_cursor = (sender.state == NSControlStateValueOn) ? 1 : 0;
    [self saveConfig];
}

- (void)thumbnailSecondsChanged:(NSStepper *)sender {
    _config->thumbnail_seconds = (int)sender.integerValue;
    [self updateThumbnailSecondsLabel];
    [self saveConfig];
}

- (void)jpegQualityChanged:(NSSlider *)sender {
    _config->jpeg_quality = (int)lround(sender.doubleValue);
    [self updateQualityLabels];
    [self saveConfig];
}

- (void)heicQualityChanged:(NSSlider *)sender {
    _config->heic_quality = (int)lround(sender.doubleValue);
    [self updateQualityLabels];
    [self saveConfig];
}

- (void)toggleCopy:(NSButton *)sender {
    _config->copy_to_clipboard = (sender.state == NSControlStateValueOn) ? 1 : 0;
    [self saveConfig];
}

- (void)toggleAutoSave:(NSButton *)sender {
    _config->auto_save = (sender.state == NSControlStateValueOn) ? 1 : 0;
    [self saveConfig];
}

- (void)toggleThumbnail:(NSButton *)sender {
    _config->show_thumbnail = (sender.state == NSControlStateValueOn) ? 1 : 0;
    [self saveConfig];
}

- (void)formatChanged:(NSPopUpButton *)sender {
    static const char *formats[] = { "png", "jpeg", "heic", "tiff" };
    NSInteger index = sender.indexOfSelectedItem;
    if (index >= 0 && index < 4) {
        (void)snprintf(_config->format, sizeof _config->format, "%s", formats[index]);
        [self saveConfig];
    }
}

- (void)chooseFolder:(id)sender {
    (void)sender;
    [NSApp activateIgnoringOtherApps:YES];

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = YES;
    panel.prompt = NSLocalizedString(@"settings.choose", nil);

    char expanded[SLIM_PATH_MAX];
    if (slim_paths_expand_tilde(_config->save_directory, expanded, sizeof expanded) == 0) {
        panel.directoryURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:expanded]
                                       isDirectory:YES];
    }

    if ([panel runModal] != NSModalResponseOK || panel.URL == nil) {
        return;
    }

    NSString *path = panel.URL.path;
    NSString *home = NSHomeDirectory();
    if ([path isEqualToString:home]) {
        path = @"~";
    } else if ([path hasPrefix:[home stringByAppendingString:@"/"]]) {
        path = [@"~" stringByAppendingString:[path substringFromIndex:home.length]];
    }

    (void)snprintf(_config->save_directory, sizeof _config->save_directory, "%s", path.UTF8String);
    [self updateFolderLabel];
    [self saveConfig];
}

- (void)openConfigFolder:(id)sender {
    (void)sender;
    char dir[SLIM_PATH_MAX];
    if (slim_paths_app_support(dir, sizeof dir) != 0) {
        return;
    }
    (void)slim_mkdir_p(dir, 0755);
    NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:dir] isDirectory:YES];
    (void)[[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)openPermissionSettings:(id)sender {
    (void)sender;
    slim_open_screen_capture_settings();
}

- (void)closeWindow:(id)sender {
    (void)sender;
    [self.window close];
}

- (void)present {
    [NSApp activateIgnoringOtherApps:YES];
    [self refreshPermissionStatus];
    [self.window makeKeyAndOrderFront:nil];
}

@end
