# 设置与关于界面布局

> 涉及文件：`src/bridge/settings.m`、`src/bridge/about.m`
> 新增设置项或调整窗口尺寸前先读这份，保持间距和对齐一致。

## 设置窗口

- 窗口宽 560pt，左右边距 24pt，内容宽 512pt。
- 表单两列：左列标签**右对齐**，固定 108pt；标签和控件间距 10pt；控件从 142pt 开始。
- 行间距 8pt；不同分区的分隔线到下一个标题 16pt；分区标题 12pt semibold、secondary 颜色。
- 复选框放在控件列，和输入框、滑块左边缘对齐，不单独缩进。
- 质量滑块固定 200pt；数值标签 32pt、等宽数字、右对齐。
- 保存目录用 12pt secondary 文本，中间省略；完整路径放 tooltip。
- 底部按钮左右分布；配置文件路径 10pt 等宽 secondary，中间省略。
- 窗口高度由 `NSStackView.fittingSize + 48` 计算，并限制在 `visibleFrame.height - 80` 内。不要写死高度，英文/中文文案长度不同。
- 当前不引入滚动视图；如果以后设置项超过一屏，再加 `NSScrollView`，不要把窗口撑出屏幕。

结构顺序：

1. 截图：包含鼠标指针
2. 截图后：剪贴板、自动保存、浮动缩略图、缩略图时长
3. 输出：格式、JPEG/HEIC 质量、保存目录
4. 权限：屏幕录制状态、打开系统设置、重启提示
5. 底部：打开配置目录 / 关闭、配置文件路径

## 关于窗口

- 窗口宽 380pt，内容居中，边距 24pt。
- 尺寸：图标 128pt、标题 26pt semibold、版本 12pt secondary、slogan 13pt、按钮行、版权 10pt tertiary。
- 图标优先从 bundle 的 `Slimshot.icns` 读取，失败再退回 `NSImageNameApplicationIcon`。
- 「复制版本信息」写入 `Slimshot / 版本 / macOS 版本` 到剪贴板。
- 「许可证」打开 bundle 内的 `LICENSE`（Makefile 负责拷贝）。
- 高度按 `fittingSize + 52` 计算，最低 360pt。

## 原则

- 用户可见文案全部走 `.strings`，中英文同步。
- 所有控件读写同一份 `slim_config_t`，不在 UI 里保存第二份状态。
- 窗口只做放得下内容的尺寸，不靠固定大留白；改变控件后重新跑一次离屏渲染检查。
