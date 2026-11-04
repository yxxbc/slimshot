/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import <Cocoa/Cocoa.h>

#include <math.h>
#include <stdio.h>
#include <string.h>

#include "config.h"
#include "paths.h"
#include "permissions.h"
#include "settings.h"
#include "settings_sidebar.h"

static const CGFloat kSettingsLabelWidth = 112.0;
static const CGFloat kSettingsPaneMargin = 24.0;
static const CGFloat kSettingsWindowWidth = 760.0;
static const CGFloat kSettingsWindowHeight = 520.0;

@implementation SettingsWindowController {
    slim_config_t *_config;
    SlimSettingsSidebarController *_sidebarController;
    NSView *_contentContainer;
    NSArray<NSView *> *_paneViews;

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
    NSTextField *_configPathLabel;
    NSString *_pluginDirectoryPath;
}

- (instancetype)initWithConfig:(slim_config_t *)config {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, kSettingsWindowWidth, kSettingsWindowHeight)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = NSLocalizedString(@"settings.title", nil);
    [window setReleasedWhenClosed:NO];
    window.contentMinSize = NSMakeSize(680.0, 460.0);

    self = [super initWithWindow:window];
    if (self != nil) {
        _config = config;
        [self buildWindowContent];
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

- (void)buildWindowContent {
    _sidebarController = [[SlimSettingsSidebarController alloc] init];

    NSViewController *contentController = [[NSViewController alloc] init];
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 550, 480)];
    contentController.view = container;
    _contentContainer = container;

    NSSplitViewController *split = [[NSSplitViewController alloc] init];
    NSSplitViewItem *sidebarItem =
        [NSSplitViewItem sidebarWithViewController:_sidebarController];
    sidebarItem.minimumThickness = 190.0;
    sidebarItem.maximumThickness = 240.0;
    sidebarItem.canCollapse = NO;
    [split addSplitViewItem:sidebarItem];

    NSSplitViewItem *contentItem =
        [NSSplitViewItem splitViewItemWithViewController:contentController];
    contentItem.minimumThickness = 440.0;
    [split addSplitViewItem:contentItem];
    split.splitView.vertical = YES;
    split.splitView.dividerStyle = NSSplitViewDividerStyleThin;

    self.window.contentViewController = split;
    [self.window setContentSize:NSMakeSize(kSettingsWindowWidth, kSettingsWindowHeight)];

    _paneViews = @[
        [self buildGeneralPane],
        [self buildCapturePane],
        [self buildOutputPane],
        [self buildHotkeysPane],
        [self buildPluginsPane],
    ];

    for (NSView *pane in _paneViews) {
        pane.translatesAutoresizingMaskIntoConstraints = NO;
        pane.hidden = YES;
        [_contentContainer addSubview:pane];
        [NSLayoutConstraint activateConstraints:@[
            [pane.leadingAnchor constraintEqualToAnchor:_contentContainer.leadingAnchor],
            [pane.trailingAnchor constraintEqualToAnchor:_contentContainer.trailingAnchor],
            [pane.topAnchor constraintEqualToAnchor:_contentContainer.topAnchor],
            [pane.bottomAnchor constraintEqualToAnchor:_contentContainer.bottomAnchor],
        ]];
    }

    __weak SettingsWindowController *weakSelf = self;
    _sidebarController.selectionHandler = ^(NSInteger row) {
        [weakSelf showPaneAtIndex:row];
    };
    _sidebarController.items = @[
        [SlimSettingsSidebarItem itemWithTitle:NSLocalizedString(@"settings.sidebar.general", nil)
                                    symbolName:@"gearshape"],
        [SlimSettingsSidebarItem itemWithTitle:NSLocalizedString(@"settings.sidebar.capture", nil)
                                    symbolName:@"camera.viewfinder"],
        [SlimSettingsSidebarItem itemWithTitle:NSLocalizedString(@"settings.sidebar.output", nil)
                                    symbolName:@"square.and.arrow.down"],
        [SlimSettingsSidebarItem itemWithTitle:NSLocalizedString(@"settings.sidebar.hotkeys", nil)
                                    symbolName:@"keyboard"],
        [SlimSettingsSidebarItem itemWithTitle:NSLocalizedString(@"settings.sidebar.plugins", nil)
                                    symbolName:@"puzzlepiece.extension"],
    ];
    [self showPaneAtIndex:0];
}

- (void)showPaneAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_paneViews.count) {
        return;
    }
    for (NSUInteger i = 0; i < _paneViews.count; i++) {
        _paneViews[i].hidden = ((NSInteger)i != index);
    }
}

- (NSView *)paneWithTitle:(NSString *)title build:(void (^)(NSStackView *stack))build {
    NSView *pane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 550, 480)];
    NSTextField *heading = [NSTextField labelWithString:title];
    heading.font = [NSFont systemFontOfSize:20.0 weight:NSFontWeightSemibold];
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    [pane addSubview:heading];

    NSStackView *stack = [NSStackView stackViewWithViews:@[]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [pane addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [heading.topAnchor constraintEqualToAnchor:pane.topAnchor
                                          constant:kSettingsPaneMargin],
        [heading.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor
                                              constant:kSettingsPaneMargin],
        [heading.trailingAnchor constraintLessThanOrEqualToAnchor:pane.trailingAnchor
                                                          constant:-kSettingsPaneMargin],
        [stack.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:16.0],
        [stack.leadingAnchor constraintEqualToAnchor:pane.leadingAnchor
                                            constant:kSettingsPaneMargin],
        [stack.trailingAnchor constraintEqualToAnchor:pane.trailingAnchor
                                             constant:-kSettingsPaneMargin],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:pane.bottomAnchor
                                                     constant:-kSettingsPaneMargin],
    ]];

    build(stack);
    return pane;
}

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

- (NSTextField *)pathLabelWithText:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:(text != nil) ? text : @""];
    label.font = [NSFont systemFontOfSize:12.0];
    label.textColor = [NSColor secondaryLabelColor];
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.maximumNumberOfLines = 1;
    [label setContentHuggingPriority:NSLayoutPriorityDefaultLow
                      forOrientation:NSLayoutConstraintOrientationHorizontal];
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                    forOrientation:NSLayoutConstraintOrientationHorizontal];
    label.toolTip = text;
    return label;
}

- (NSTextField *)hotkeyLabelForSpec:(const char *)spec {
    NSString *value = (spec != NULL && spec[0] != '\0')
                          ? [NSString stringWithUTF8String:spec]
                          : @"—";
    value = [value lowercaseString];
    value = [value stringByReplacingOccurrencesOfString:@"cmd+" withString:@"⌘"];
    value = [value stringByReplacingOccurrencesOfString:@"shift+" withString:@"⇧"];
    value = [value stringByReplacingOccurrencesOfString:@"alt+" withString:@"⌥"];
    value = [value stringByReplacingOccurrencesOfString:@"ctrl+" withString:@"⌃"];
    value = [value uppercaseString];

    NSTextField *label = [NSTextField labelWithString:value];
    label.font = [NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightRegular];
    return label;
}

- (NSView *)buildGeneralPane {
    return [self paneWithTitle:NSLocalizedString(@"settings.sidebar.general", nil)
                          build:^(NSStackView *stack) {
        [self addSectionHeader:NSLocalizedString(@"settings.permission.section", nil)
                       toStack:stack];

        _permissionStatusLabel = [NSTextField labelWithString:@""];
        _permissionStatusLabel.font = [NSFont systemFontOfSize:13.0
                                                        weight:NSFontWeightMedium];
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

        [self addSectionHeader:NSLocalizedString(@"settings.config.section", nil)
                       toStack:stack];

        char configPath[SLIM_PATH_MAX];
        NSString *path = @"";
        if (slim_paths_config(configPath, sizeof configPath) == 0) {
            path = [NSString stringWithUTF8String:configPath] ?: @"";
        }
        _configPathLabel = [self pathLabelWithText:path];
        NSButton *openConfigButton =
            [NSButton buttonWithTitle:NSLocalizedString(@"settings.open_config", nil)
                               target:self
                               action:@selector(openConfigFolder:)];
        NSStackView *configControl =
            [NSStackView stackViewWithViews:@[ _configPathLabel, openConfigButton ]];
        configControl.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        configControl.alignment = NSLayoutAttributeCenterY;
        configControl.spacing = 8.0;
        [configControl setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                  forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addRowToStack:stack
                      label:NSLocalizedString(@"settings.config_path_label", nil)
                    control:configControl];
    }];
}

- (NSView *)buildCapturePane {
    return [self paneWithTitle:NSLocalizedString(@"settings.sidebar.capture", nil)
                          build:^(NSStackView *stack) {
        [self addSectionHeader:NSLocalizedString(@"settings.capture_options", nil)
                       toStack:stack];
        _includeCursorCheck =
            [NSButton checkboxWithTitle:NSLocalizedString(@"settings.include_cursor", nil)
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

        _thumbnailCheck =
            [NSButton checkboxWithTitle:NSLocalizedString(@"settings.thumbnail", nil)
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
    }];
}

- (NSView *)buildOutputPane {
    return [self paneWithTitle:NSLocalizedString(@"settings.sidebar.output", nil)
                          build:^(NSStackView *stack) {
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
    }];
}

- (NSView *)buildHotkeysPane {
    return [self paneWithTitle:NSLocalizedString(@"settings.sidebar.hotkeys", nil)
                          build:^(NSStackView *stack) {
        [self addSectionHeader:NSLocalizedString(@"settings.hotkeys.section", nil)
                       toStack:stack];

        NSTextField *fullscreen = [self hotkeyLabelForSpec:_config->hotkey_fullscreen];
        [self addRowToStack:stack
                      label:NSLocalizedString(@"settings.hotkeys.fullscreen", nil)
                    control:fullscreen];

        NSTextField *window = [self hotkeyLabelForSpec:_config->hotkey_window];
        [self addRowToStack:stack
                      label:NSLocalizedString(@"settings.hotkeys.window", nil)
                    control:window];

        NSTextField *region = [self hotkeyLabelForSpec:_config->hotkey_region];
        [self addRowToStack:stack
                      label:NSLocalizedString(@"settings.hotkeys.region", nil)
                    control:region];

        NSTextField *hint =
            [NSTextField labelWithString:NSLocalizedString(@"settings.hotkeys.hint", nil)];
        hint.font = [NSFont systemFontOfSize:11.0];
        hint.textColor = [NSColor secondaryLabelColor];
        [self addRowToStack:stack label:@"" control:hint];

        NSButton *openConfigButton =
            [NSButton buttonWithTitle:NSLocalizedString(@"settings.hotkeys.open_config", nil)
                               target:self
                               action:@selector(openConfigFile:)];
        [self addRowToStack:stack label:@"" control:openConfigButton];
    }];
}

- (NSView *)buildPluginsPane {
    return [self paneWithTitle:NSLocalizedString(@"settings.sidebar.plugins", nil)
                          build:^(NSStackView *stack) {
        [self addSectionHeader:NSLocalizedString(@"settings.plugins.directory", nil)
                       toStack:stack];

        char directory[SLIM_PATH_MAX];
        NSString *path = @"";
        if (slim_paths_app_support(directory, sizeof directory) == 0) {
            size_t length = strlen(directory);
            (void)snprintf(directory + length, sizeof directory - length, "/Plugins");
            path = [NSString stringWithUTF8String:directory] ?: @"";
            _pluginDirectoryPath = path;
        }

        NSTextField *pathLabel = [self pathLabelWithText:path];
        NSButton *openButton =
            [NSButton buttonWithTitle:NSLocalizedString(@"settings.plugins.open", nil)
                               target:self
                               action:@selector(openPluginFolder:)];
        NSStackView *control =
            [NSStackView stackViewWithViews:@[ pathLabel, openButton ]];
        control.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        control.alignment = NSLayoutAttributeCenterY;
        control.spacing = 8.0;
        [control setContentHuggingPriority:NSLayoutPriorityDefaultLow
                           forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addRowToStack:stack
                      label:NSLocalizedString(@"settings.plugins.user", nil)
                    control:control];

        NSTextField *hint =
            [NSTextField labelWithString:NSLocalizedString(@"settings.plugins.hint", nil)];
        hint.font = [NSFont systemFontOfSize:11.0];
        hint.textColor = [NSColor secondaryLabelColor];
        [self addRowToStack:stack label:@"" control:hint];
    }];
}

- (void)refreshControls {
    _includeCursorCheck.state =
        _config->include_cursor ? NSControlStateValueOn : NSControlStateValueOff;
    _copyCheck.state =
        _config->copy_to_clipboard ? NSControlStateValueOn : NSControlStateValueOff;
    _autoSaveCheck.state =
        _config->auto_save ? NSControlStateValueOn : NSControlStateValueOff;
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
    if (_permissionStatusLabel == nil) {
        return;
    }
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

    (void)snprintf(_config->save_directory, sizeof _config->save_directory, "%s",
                   path.UTF8String);
    [self updateFolderLabel];
    [self saveConfig];
}

- (void)openConfigFolder:(id)sender {
    (void)sender;
    char directory[SLIM_PATH_MAX];
    if (slim_paths_app_support(directory, sizeof directory) != 0) {
        return;
    }
    (void)slim_mkdir_p(directory, 0755);
    NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:directory]
                            isDirectory:YES];
    (void)[[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)openConfigFile:(id)sender {
    char path[SLIM_PATH_MAX];
    if (slim_paths_config(path, sizeof path) != 0) {
        return;
    }
    NSString *file = [NSString stringWithUTF8String:path];
    if (![[NSFileManager defaultManager] fileExistsAtPath:file]) {
        [self openConfigFolder:sender];
        return;
    }
    (void)[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:file]];
}

- (void)openPluginFolder:(id)sender {
    (void)sender;
    if (_pluginDirectoryPath.length == 0) {
        return;
    }
    (void)slim_mkdir_p(_pluginDirectoryPath.fileSystemRepresentation, 0755);
    NSURL *url = [NSURL fileURLWithPath:_pluginDirectoryPath isDirectory:YES];
    (void)[[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)openPermissionSettings:(id)sender {
    (void)sender;
    slim_open_screen_capture_settings();
}

- (void)present {
    [NSApp activateIgnoringOtherApps:YES];
    [self refreshPermissionStatus];
    [self.window makeKeyAndOrderFront:nil];
}

@end
