# 设置与关于界面布局

> 涉及文件：`src/bridge/settings.m`、`src/bridge/settings_sidebar.m`、`src/bridge/about.m`
> 新增设置项或调整窗口尺寸前先读这份，保持间距和对齐一致。

## 设置窗口

- 窗口 760×520pt，最小 680×460pt，可缩放。
- 左侧边栏 210pt（190–240pt），`NSVisualEffectView` 的 sidebar 材质 + source list 表格；每一行是 18pt SF Symbol + 13pt 标签。
- 右侧内容区约 550pt；每个面板顶部是 20pt semibold 标题，边距 24pt。
- 表单两列：左列标签**右对齐**，固定 112pt；标签和控件间距 10pt；控件从 146pt 开始。
- 行间距 8pt；分区标题 12pt semibold、secondary 颜色；分隔线到下一个标题 16pt。
- 复选框放在控件列，和输入框、滑块左边缘对齐，不单独缩进。
- 质量滑块固定 200pt；数值标签 32pt、等宽数字、右对齐。
- 路径文本用 12pt secondary、中间省略，完整路径放 tooltip。
- 面板内容超过窗口高度时以后再加滚动视图；当前五个面板都控制在一屏内。

侧边栏顺序与内容：

1. **通用**：屏幕录制权限状态/打开系统设置、重启提示、配置文件路径/打开配置目录
2. **截图**：包含鼠标指针；截图后的剪贴板、自动保存、浮动缩略图、缩略图时长
3. **输出**：格式、JPEG/HEIC 质量、保存目录
4. **热键**：当前全屏/窗口/区域热键（只读，符号显示）、修改说明、打开配置文件
5. **插件**：用户插件目录、打开插件目录、已安装插件列表、从菜单栏运行的说明

关于窗口继续放在菜单「关于 Slimshot」，不在侧边栏里重复。

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
- 侧边栏只负责切换面板，面板视图常驻并用 `hidden` 切换，避免反复增删约束。
- 改变控件后重新跑一次离屏渲染检查，至少看默认面板和设置项最多的面板。
