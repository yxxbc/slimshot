/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import "overlay_action_rail.h"

static const CGFloat kRailWidth = 44.0;
static const CGFloat kRailRow = 34.0;
static const CGFloat kRailPadding = 6.0;
static const CGFloat kRailSeparator = 9.0;
static const CGFloat kRailButtonInset = 6.0;
static const CGFloat kRailButtonSize = 32.0;
static const NSInteger kRailVisiblePlugins = 4;

@interface SlimRailButton : NSButton
@end

@implementation SlimRailButton {
    NSTrackingArea *_hoverArea;
    BOOL _hovered;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_hoverArea != nil) {
        [self removeTrackingArea:_hoverArea];
    }
    _hoverArea = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways |
                      NSTrackingInVisibleRect)
               owner:self
            userInfo:nil];
    [self addTrackingArea:_hoverArea];
}

- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    _hovered = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    _hovered = NO;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    if (_hovered) {
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.14] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1.0, 1.0)
                                         xRadius:6.0
                                         yRadius:6.0] fill];
    }
    [super drawRect:dirtyRect];
}

@end

@implementation SlimOverlayActionRail {
    NSArray<SlimOverlayPluginAction *> *_actions;
    NSMutableArray<SlimRailButton *> *_pluginButtons;
    SlimRailButton *_overflowButton;
    SlimRailButton *_captureButton;
    SlimRailButton *_cancelButton;
    CGFloat _separatorY;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self != nil) {
        _pluginButtons = [NSMutableArray array];
        [self buildStaticButtons];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)buildStaticButtons {
    _captureButton = [self makeButtonWithSymbol:@"checkmark"
                                          title:NSLocalizedString(@"overlay.capture", nil)
                                        toolTip:NSLocalizedString(@"overlay.capture.tooltip", nil)
                                         action:@selector(capturePressed:)];
    _captureButton.identifier = @"slimshot.capture";
    _cancelButton = [self makeButtonWithSymbol:@"xmark"
                                         title:NSLocalizedString(@"overlay.cancel", nil)
                                       toolTip:NSLocalizedString(@"overlay.cancel.tooltip", nil)
                                        action:@selector(cancelPressed:)];
    _cancelButton.identifier = @"slimshot.cancel";
}

- (SlimRailButton *)makeButtonWithSymbol:(NSString *)symbol
                                   title:(NSString *)title
                                 toolTip:(NSString *)toolTip
                                  action:(SEL)action {
    SlimRailButton *button = [[SlimRailButton alloc] initWithFrame:NSZeroRect];
    button.bordered = NO;
    NSImage *image = [NSImage imageWithSystemSymbolName:symbol
                                 accessibilityDescription:title];
    if (image == nil) {
        image = [NSImage imageWithSystemSymbolName:@"puzzlepiece.extension"
                            accessibilityDescription:title];
    }
    button.image = image;
    button.contentTintColor = [NSColor whiteColor];
    button.toolTip = toolTip;
    button.title = title;
    button.imagePosition = NSImageOnly;
    button.refusesFirstResponder = YES;
    button.target = self;
    button.action = action;
    [self addSubview:button];
    return button;
}

- (void)setPluginActions:(NSArray<SlimOverlayPluginAction *> *)actions {
    _actions = [actions copy];
    [self rebuildPluginButtons];
    [self setNeedsLayout:YES];
    [self setNeedsDisplay:YES];
}

- (void)rebuildPluginButtons {
    for (SlimRailButton *button in _pluginButtons) {
        [button removeFromSuperview];
    }
    [_pluginButtons removeAllObjects];
    [_overflowButton removeFromSuperview];
    _overflowButton = nil;

    BOOL overflow = _actions.count > kRailVisiblePlugins;
    NSUInteger visible = overflow ? (NSUInteger)kRailVisiblePlugins : _actions.count;
    for (NSUInteger i = 0; i < visible; i++) {
        SlimOverlayPluginAction *action = _actions[i];
        NSString *toolTip =
            [NSString stringWithFormat:@"%@ (%lu)", action.title, (unsigned long)(i + 1)];
        SlimRailButton *button = [self makeButtonWithSymbol:action.iconName
                                                      title:action.title
                                                    toolTip:toolTip
                                                     action:@selector(pluginPressed:)];
        button.identifier = action.identifier;
        [_pluginButtons addObject:button];
    }
    if (overflow) {
        _overflowButton = [self makeButtonWithSymbol:@"ellipsis"
                                               title:NSLocalizedString(@"overlay.more", nil)
                                             toolTip:NSLocalizedString(@"overlay.more", nil)
                                              action:@selector(overflowPressed:)];
    }
}

- (NSSize)preferredSize {
    NSUInteger pluginRows = _pluginButtons.count + (_overflowButton != nil ? 1 : 0);
    CGFloat height = kRailPadding * 2.0 + (pluginRows + 2) * kRailRow;
    if (pluginRows > 0) {
        height += kRailSeparator;
    }
    return NSMakeSize(kRailWidth, height);
}

- (void)layout {
    [super layout];
    CGFloat y = kRailPadding;
    for (SlimRailButton *button in _pluginButtons) {
        button.frame = NSMakeRect(kRailButtonInset, y + 2.0,
                                  kRailButtonSize, kRailButtonSize - 4.0);
        y += kRailRow;
    }
    if (_overflowButton != nil) {
        _overflowButton.frame = NSMakeRect(kRailButtonInset, y + 2.0,
                                           kRailButtonSize, kRailButtonSize - 4.0);
        y += kRailRow;
    }
    _separatorY = y + 3.0;
    if (_pluginButtons.count > 0 || _overflowButton != nil) {
        y += kRailSeparator;
    }
    _captureButton.frame = NSMakeRect(kRailButtonInset, y + 2.0,
                                      kRailButtonSize, kRailButtonSize - 4.0);
    y += kRailRow;
    _cancelButton.frame = NSMakeRect(kRailButtonInset, y + 2.0,
                                     kRailButtonSize, kRailButtonSize - 4.0);
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect bounds = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *background =
        [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:11.0 yRadius:11.0];
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.86] setFill];
    [background fill];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.12] setStroke];
    background.lineWidth = 1.0;
    [background stroke];

    if (_pluginButtons.count > 0 || _overflowButton != nil) {
        NSBezierPath *separator = [NSBezierPath bezierPath];
        [separator moveToPoint:NSMakePoint(9.0, _separatorY)];
        [separator lineToPoint:NSMakePoint(self.bounds.size.width - 9.0, _separatorY)];
        [[NSColor colorWithCalibratedWhite:1.0 alpha:0.16] setStroke];
        separator.lineWidth = 1.0;
        [separator stroke];
    }

    [[NSColor systemBlueColor] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(_captureButton.frame, 2.0, 2.0)
                                     xRadius:7.0
                                     yRadius:7.0] fill];
    [[NSColor colorWithCalibratedWhite:0.34 alpha:1.0] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(_cancelButton.frame, 2.0, 2.0)
                                     xRadius:7.0
                                     yRadius:7.0] fill];
}

- (void)pluginPressed:(SlimRailButton *)sender {
    NSString *identifier = sender.identifier;
    if (identifier.length > 0 && self.pluginHandler != nil) {
        self.pluginHandler(identifier);
    }
}

- (void)capturePressed:(id)sender {
    (void)sender;
    if (self.captureHandler != nil) {
        self.captureHandler();
    }
}

- (void)cancelPressed:(id)sender {
    (void)sender;
    if (self.cancelHandler != nil) {
        self.cancelHandler();
    }
}

- (void)overflowPressed:(id)sender {
    (void)sender;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    for (SlimOverlayPluginAction *action in _actions) {
        NSMenuItem *item =
            [[NSMenuItem alloc] initWithTitle:action.title
                                       action:@selector(overflowSelected:)
                                keyEquivalent:@""];
        item.target = self;
        item.representedObject = action.identifier;
        item.image = [NSImage imageWithSystemSymbolName:action.iconName
                              accessibilityDescription:action.title];
        [menu addItem:item];
    }
    NSPoint location = NSMakePoint(NSMaxX(self.bounds) + 4.0, NSMinY(self.bounds));
    [menu popUpMenuPositioningItem:nil atLocation:location inView:self];
}

- (void)overflowSelected:(NSMenuItem *)sender {
    NSString *identifier = sender.representedObject;
    if (identifier.length > 0 && self.pluginHandler != nil) {
        self.pluginHandler(identifier);
    }
}

- (void)mouseDown:(NSEvent *)event {
    (void)event;
}

- (void)rightMouseDown:(NSEvent *)event {
    (void)event;
}

@end
