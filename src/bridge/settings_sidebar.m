/*
 * Slimshot — lightweight macOS screenshot tool
 * Copyright (C) 2026 Slimshot contributors
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import "settings_sidebar.h"

@interface SlimSettingsSidebarController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation SlimSettingsSidebarItem
+ (instancetype)itemWithTitle:(NSString *)title symbolName:(NSString *)symbolName {
    SlimSettingsSidebarItem *item = [[self alloc] init];
    item.title = title;
    item.symbolName = symbolName;
    return item;
}
@end

@implementation SlimSettingsSidebarController {
    NSTableView *_tableView;
}

- (void)loadView {
    NSVisualEffectView *effect =
        [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 210, 480)];
    effect.material = NSVisualEffectMaterialSidebar;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.state = NSVisualEffectStateFollowsWindowActiveState;
    self.view = effect;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    [effect addSubview:scroll];

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.style = NSTableViewStyleSourceList;
    _tableView.headerView = nil;
    _tableView.rowSizeStyle = NSTableViewRowSizeStyleDefault;
    _tableView.rowHeight = 28.0;
    _tableView.intercellSpacing = NSMakeSize(0.0, 2.0);
    _tableView.allowsEmptySelection = NO;
    _tableView.allowsMultipleSelection = NO;
    _tableView.backgroundColor = [NSColor clearColor];
    _tableView.dataSource = self;
    _tableView.delegate = self;

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"main"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:column];
    _tableView.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    scroll.documentView = _tableView;

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:effect.topAnchor constant:8.0],
        [scroll.leadingAnchor constraintEqualToAnchor:effect.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:effect.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:effect.bottomAnchor],
    ]];
}

- (void)setItems:(NSArray<SlimSettingsSidebarItem *> *)items {
    _items = [items copy];
    [_tableView reloadData];
    if (_items.count > 0) {
        [self selectRow:0];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)_items.count;
}

- (NSView *)tableView:(NSTableView *)tableView
    viewForTableColumn:(NSTableColumn *)tableColumn
                   row:(NSInteger)row {
    (void)tableColumn;
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"SidebarCell" owner:self];
    if (cell == nil) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 28)];
        cell.identifier = @"SidebarCell";

        NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.imageScaling = NSImageScaleProportionallyDown;
        [cell addSubview:imageView];
        cell.imageView = imageView;

        NSTextField *label = [NSTextField labelWithString:@""];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.font = [NSFont systemFontOfSize:13.0];
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:label];
        cell.textField = label;

        [NSLayoutConstraint activateConstraints:@[
            [imageView.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8.0],
            [imageView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [imageView.widthAnchor constraintEqualToConstant:18.0],
            [imageView.heightAnchor constraintEqualToConstant:18.0],
            [label.leadingAnchor constraintEqualToAnchor:imageView.trailingAnchor constant:8.0],
            [label.trailingAnchor constraintLessThanOrEqualToAnchor:cell.trailingAnchor
                                                          constant:-8.0],
            [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }

    SlimSettingsSidebarItem *item = _items[row];
    cell.textField.stringValue = item.title;
    NSImage *image = [NSImage imageWithSystemSymbolName:item.symbolName
                              accessibilityDescription:item.title];
    cell.imageView.image = image;
    cell.imageView.contentTintColor = [NSColor controlAccentColor];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    NSInteger row = _tableView.selectedRow;
    if (row >= 0 && _selectionHandler != nil) {
        _selectionHandler(row);
    }
}

- (void)selectRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_items.count) {
        return;
    }
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
            byExtendingSelection:NO];
    [_tableView scrollRowToVisible:row];
}

@end
