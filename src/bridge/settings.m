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
    NSStackView *_rootStack;
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
        initWithContentRect:NSMakeRect(0, 0, 560, 600)
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

static const CGFloat kSettingsLabelWidth = 108.0;
static const CGFloat kSettingsMargin = 24.0;

- (NSTextField *)formLabel:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.alignment = NSTextAlignmentRight;
    label.font = [NSFont systemFontOfSize:13.0];
    [label.widthAnchor constraintEqualToConstant:kSettingsLabelWidth].active = YES;
    return label;
}

- (NSStackView *)formRowWithLabel:(NSString *)text control:(NSView *)control {
    NSStackView *row = [NSStackView stackViewWithViews:@[ [self formLabel:text], control ]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 10.0;
    return row;
}

- (void)addRowToStack:(NSStackView *)stack
                label:(NSString *)label
              control:(NSView *)control {
    NSStackView *row = [self formRowWithLabel:label control:control];
    [stack addArrangedSubview:row];
    [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}

- (void)addCheckboxRowToStack:(NSStackView *)stack checkbox:(NSButton *)checkbox {
    [self addRowToStack:stack label:@"" control:checkbox];
}

- (void)addSectionHeader:(NSString *)title toStack:(NSStackView *)stack {
    if (stack.arrangedSubviews.count > 0) {
        NSBox *separator = [[NSBox alloc] init];
        separator.boxType = NSBoxSeparator;
        [stack addArrangedSubview:separator];
        [separator.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        [stack setCustomSpacing:16.0 afterView:separator];
    }

    NSTextField *header = [NSTextField labelWithString:title];
    header.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold];
    header.textColor = [NSColor secondaryLabelColor];
    [stack addArrangedSubview:header];
    [stack setCustomSpacing:10.0 afterView:header];
}

- (void)buildUI {
    NSView *content = self.window.contentView;
    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];
    _rootStack = stack;

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor
                                            constant:kSettingsMargin],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor
                                             constant:-kSettingsMargin],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor
                                        constant:kSettingsMargin],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor
                                                     constant:-kSettingsMargin],
    ]];

    [self addSectionHeader:NSLocalizedString(@"settings.capture_options", nil) toStack:stack];
    _includeCursorCheck = [NSButton checkboxWithTitle:NSLocalizedString(@"settings.include_cursor", nil)
                                               target:self
                                               action:@selector(toggleIncludeCursor:)];
    [self addCheckboxRowToStack:stack checkbox:_includeCursorCheck];

    [self addSectionHeader:NSLocalizedString(@"settings.capture", nil) toStack:stack];
    _copyCheck = [NSButton checkboxWithTitle:NSLocalizedString(@"settings.copy", nil)
                                      target:self
                                      action:@selector(toggleCopy:)];
    [self addCheckboxRowToStack:stack checkbox:_copyCheck];

    _autoSaveCheck = [NSButton checkboxWithTitle:NSLocalizedString(@"settings.auto_save", nil)
                                          target:self
                                          action:@selector(toggleAutoSave:)];
    [self addCheckboxRowToStack:stack checkbox:_autoSaveCheck];

    _thumbnailCheck = [NSButton checkboxWithTitle:NSLocalizedString(@"settings.thumbnail", nil)
                                           target:self
                                           action:@selector(toggleThumbnail:)];
    [self addCheckboxRowToStack:stack checkbox:_thumbnailCheck];

    _thumbnailStepper = [[NSStepper alloc] init];
    _thumbnailStepper.minValue = 0;
    _thumbnailStepper.maxValue = 60;
    _thumbnailStepper.increment = 1;
    _thumbnailStepper.target = self;
    _thumbnailStepper.action = @selector(thumbnailSecondsChanged:);
    _thumbnailSecondsLabel = [NSTextField labelWithString:@""];
    _thumbnailSecondsLabel.font = [NSFont systemFontOfSize:12.0];
    _thumbnailSecondsLabel.textColor = [NSColor secondaryLabelColor];
    NSStackView *secondsControl =
        [NSStackView stackViewWithViews:@[ _thumbnailStepper, _thumbnailSecondsLabel ]];
    secondsControl.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    secondsControl.alignment = NSLayoutAttributeCenterY;
    secondsControl.spacing = 8.0;
    [self addRowToStack:stack
                  label:NSLocalizedString(@"settings.thumbnail_seconds_label", nil)
                control:secondsControl];

    [self addSectionHeader:NSLocalizedString(@"settings.output", nil) toStack:stack];
    _formatPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_formatPopup addItemsWithTitles:@[ @"PNG", @"JPEG", @"HEIC", @"TIFF" ]];
    _formatPopup.target = self;
    _formatPopup.action = @selector(formatChanged:);
    [self addRowToStack:stack
                  label:NSLocalizedString(@"settings.format", nil)
                control:_formatPopup];

    _jpegSlider = [NSSlider sliderWithValue:_config->jpeg_quality
                                   minValue:1.0
                                   maxValue:100.0
                                     target:self
                                     action:@selector(jpegQualityChanged:)];
    _jpegSlider.continuous = NO;
    [_jpegSlider.widthAnchor constraintEqualToConstant:200.0].active = YES;
    _jpegValueLabel = [NSTextField labelWithString:@""];
    _jpegValueLabel.alignment = NSTextAlignmentRight;
    _jpegValueLabel.font = [NSFont monospacedDigitSystemFontOfSize:12.0
                                                           weight:NSFontWeightRegular];
    [_jpegValueLabel.widthAnchor constraintEqualToConstant:32.0].active = YES;
    NSStackView *jpegControl =
        [NSStackView stackViewWithViews:@[ _jpegSlider, _jpegValueLabel ]];
    jpegControl.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    jpegControl.alignment = NSLayoutAttributeCenterY;
    jpegControl.spacing = 8.0;
    [self addRowToStack:stack
                  label:NSLocalizedString(@"settings.quality.jpeg", nil)
                control:jpegControl];

    _heicSlider = [NSSlider sliderWithValue:_config->heic_quality
                                   minValue:1.0
                                   maxValue:100.0
                                     target:self
                                     action:@selector(heicQualityChanged:)];
    _heicSlider.continuous = NO;
    [_heicSlider.widthAnchor constraintEqualToConstant:200.0].active = YES;
    _heicValueLabel = [NSTextField labelWithString:@""];
    _heicValueLabel.alignment = NSTextAlignmentRight;
    _heicValueLabel.font = [NSFont monospacedDigitSystemFontOfSize:12.0
                                                           weight:NSFontWeightRegular];
    [_heicValueLabel.widthAnchor constraintEqualToConstant:32.0].active = YES;
    NSStackView *heicControl =
        [NSStackView stackViewWithViews:@[ _heicSlider, _heicValueLabel ]];
    heicControl.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    heicControl.alignment = NSLayoutAttributeCenterY;
    heicControl.spacing = 8.0;
    [self addRowToStack:stack
                  label:NSLocalizedString(@"settings.quality.heic", nil)
                control:heicControl];

    _folderLabel = [NSTextField labelWithString:@""];
    _folderLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _folderLabel.maximumNumberOfLines = 1;
    _folderLabel.font = [NSFont systemFontOfSize:12.0];
    _folderLabel.textColor = [NSColor secondaryLabelColor];
    [_folderLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow
                             forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_folderLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                           forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_folderLabel.widthAnchor constraintGreaterThanOrEqualToConstant:220.0].active = YES;

    NSButton *chooseButton = [NSButton buttonWithTitle:NSLocalizedString(@"settings.choose", nil)
                                                target:self
                                                action:@selector(chooseFolder:)];
    NSStackView *folderControl =
        [NSStackView stackViewWithViews:@[ _folderLabel, chooseButton ]];
    folderControl.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    folderControl.alignment = NSLayoutAttributeCenterY;
    folderControl.spacing = 8.0;
    [folderControl setContentHuggingPriority:NSLayoutPriorityDefaultLow
                              forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addRowToStack:stack
                  label:NSLocalizedString(@"settings.folder_label", nil)
                control:folderControl];

    [self addSectionHeader:NSLocalizedString(@"settings.permission.section", nil) toStack:stack];
    _permissionStatusLabel = [NSTextField labelWithString:@""];
    _permissionStatusLabel.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    NSButton *permissionButton =
        [NSButton buttonWithTitle:NSLocalizedString(@"settings.permission", nil)
                           target:self
                           action:@selector(openPermissionSettings:)];
    NSStackView *permissionControl =
        [NSStackView stackViewWithViews:@[ _permissionStatusLabel, permissionButton ]];
    permissionControl.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    permissionControl.alignment = NSLayoutAttributeCenterY;
    permissionControl.spacing = 12.0;
    [self addRowToStack:stack
                  label:NSLocalizedString(@"settings.permission.label", nil)
                control:permissionControl];

    NSTextField *permissionHint =
        [NSTextField labelWithString:NSLocalizedString(@"settings.permission.restart", nil)];
    permissionHint.font = [NSFont systemFontOfSize:11.0];
    permissionHint.textColor = [NSColor secondaryLabelColor];
    [self addRowToStack:stack label:@"" control:permissionHint];

    NSButton *openConfigButton =
        [NSButton buttonWithTitle:NSLocalizedString(@"settings.open_config", nil)
                           target:self
                           action:@selector(openConfigFolder:)];
    NSButton *closeButton = [NSButton buttonWithTitle:NSLocalizedString(@"settings.close", nil)
                                               target:self
                                               action:@selector(closeWindow:)];
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                       forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *buttonRow =
        [NSStackView stackViewWithViews:@[ openConfigButton, spacer, closeButton ]];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.alignment = NSLayoutAttributeCenterY;
    buttonRow.spacing = 8.0;
    buttonRow.distribution = NSStackViewDistributionFill;
    [stack addArrangedSubview:buttonRow];
    [buttonRow.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;

    char configPath[SLIM_PATH_MAX];
    if (slim_paths_config(configPath, sizeof configPath) == 0) {
        NSString *path = [NSString stringWithUTF8String:configPath];
        NSTextField *pathLabel = [NSTextField labelWithString:
            [NSString stringWithFormat:NSLocalizedString(@"settings.config_path", nil), path]];
        pathLabel.font = [NSFont monospacedSystemFontOfSize:10.0 weight:NSFontWeightRegular];
        pathLabel.textColor = [NSColor secondaryLabelColor];
        pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [stack addArrangedSubview:pathLabel];
        [pathLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }

    [stack layoutSubtreeIfNeeded];
    NSSize fitting = stack.fittingSize;
    CGFloat height = (fitting.height > 100.0) ? fitting.height + kSettingsMargin * 2.0 : 600.0;
    CGFloat maxHeight = [NSScreen mainScreen].visibleFrame.size.height - 80.0;
    height = MIN(height, maxHeight);
    [self.window setContentSize:NSMakeSize(560.0, height)];
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
    _folderLabel.stringValue = path;
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
