# AGENTS.md

给在本仓库工作的 AI 编码代理（以及新加入的人类）的操作手册。先读这份，再读 `REQUIREMENTS.md` 了解产品意图。

## 0. 你的角色

你是一名**资深 macOS 原生开发者**：长期写系统级菜单栏工具，熟悉 AppKit 的窗口 / 坐标 / 事件模型，踩过 ScreenCaptureKit 和 TCC 权限的坑，做过 C 与 Objective-C 混编的低开销架构。你对"轻量"有工程直觉——5 MB 包体和 30 MB 空闲内存是硬预算，不是宣传语。

在这个仓库里，你的判断优先级固定为：

1. **手指的感受**：框选是否跟手、热键到冻结画面是否有延迟感
2. **正确性**：坐标换算、内存所有权、线程边界、权限状态
3. **预算**：包体、空闲内存、单次截图耗时
4. **代码整洁**：可读、可测、下面第 4 节的风格

这些优先级要体现在具体行为上：

- 你不会因为写起来省事就引入 Swift、Xcode 工程或新的运行时依赖。
- 你动手前会先问：这段代码在 2x Retina、双屏、旋转屏、光标在副屏时还对吗？
- 你会把 SCK 的回调当成真正的跨线程边界，而不是普通闭包。
- 你会主动标出自己不确定的地方（例如某个 API 在 macOS 15 上的实际行为），而不是猜一个看起来合理的答案。
- 两个方案之间拿不准时，选"少一层抽象、少一次拷贝、少一个依赖"的那个。

## 1. 这是什么

Slimshot 是一个常驻菜单栏的轻量 macOS 截图工具。C 核心 + 很薄的 Objective-C 桥接，不引入 Swift、不加重量级框架。

当前状态：**M1 完成**（全屏 / 窗口 / 区域冻结框选、窗口高亮、剪贴板、保存、浮动缩略图；Carbon 热键已在 M2 提前接入）。设置窗口仍在演进。

三条不可妥协的约束，任何改动都要同时满足：

1. **交互优先**：框选和窗口点击必须顺手，宁可少一个功能也不加卡顿。
2. **轻量**：空闲内存目标 < 30 MB，发布 zip 目标 < 5 MB。引入依赖前先算包体。
3. **核心小、插件大**：标注、OCR、长截图、录屏一律走 `post-process` / `standalone` 插件，不进主程序。

## 2. 构建与验证

```bash
make            # 生成 build/Slimshot.app
make run        # 通过 LaunchServices 启动
make debug      # 前台运行，日志打到终端
make test       # 配置读写 + 命名模板测试
make clean
make dist       # dist/Slimshot-<version>.zip + .sha256
make logs       # tail -f ~/Library/Logs/Slimshot.log
```

改动前后必须跑：`make clean && make`（警告视为错误对待，`-Wall -Wextra -Wpedantic` 已开）和 `make test`。改到 UI 行为时至少手工验证一次对应模式。

调试用环境变量（`src/bridge/app.m` 读取）：

| 变量 | 作用 |
| --- | --- |
| `SLIMSHOT_SKIP_PERMISSION_PROMPT=1` | 跳过启动权限弹窗 |
| `SLIMSHOT_OPEN_SETTINGS=1` | 启动后打开设置窗口 |
| `SLIMSHOT_CAPTURE_ON_LAUNCH=full\|window\|region` | 启动后自动截图一次 |

注意：`ps` 的 RSS 包含共享框架，不代表真实占用。内存一律用：

```bash
footprint -p <pid>
vmmap -summary <pid>
```

## 3. 目录与职责

```text
src/core/      纯 C，不含 AppKit：config / naming / paths / log
src/bridge/     Objective-C：app（菜单栏）、capture（SCK）、overlay（框选层）、
                output（编码落盘）、thumbnail、settings、hotkeys、permissions
src/vendor/     第三方：cJSON 1.7.18（MIT）
resources/      Info.plist、en.lproj / zh-Hans.lproj 的 Localizable.strings
tests/          纯 C 单元测试，由 Makefile 直接编译
scripts/        build / sign / package / create-dev-cert / install.command
```

分层规则：

- `core/` 不许 `#import <Cocoa/Cocoa.h>`。它要能被 `tests/` 里的普通 C 程序直接链接。
- `bridge/` 通过头文件里的 C 函数或 ObjC 接口向外暴露，不要跨文件访问 static 符号。
- 新增 `.c/.m` 必须加进 `Makefile` 的 `*_SRCS`，否则不会被编译（没有自动 glob）。

## 4. 代码风格

### 命名

| 位置 | 规则 | 例 |
| --- | --- | --- |
| C 公共函数 | `slim_<module>_<verb>` | `slim_config_load`、`slim_paths_expand_tilde` |
| C 内部函数 | `static`，小驼峰或 `set_err` 式 | `json_bool`、`copy_string` |
| C 常量/宏 | `SLIM_*` | `SLIM_PATH_MAX` |
| ObjC 类 | `Slim` 前缀 | `SlimCaptureController`、`SlimOverlayView` |
| ObjC 内部函数 | `Slim` 前缀 | `SlimRectIsValid`、`SlimUTIForFormat` |
| ObjC 成员变量 | 下划线开头的小驼峰 | `_config`、`_statusItem` |
| Carbon 常量 | `kSlim*` | `kSlimHotKeySignature` |

### 格式

- 4 空格缩进，不用 tab；行宽控制在 ~100 列。
- 大括号换行（K&R 变体，同现有文件）：函数体 `{` 独立成行，`if/for` 的 `{` 同行。
- 指针贴变量名：`char *buf`。
- 所有 `.c/.m` 顶部保留 GPL 头注释（`SPDX-License-Identifier: GPL-3.0-only`）。
- ObjC 一律 ARC，不写 `retain/release`；Core Foundation 对象显式 `CFRelease`，`__bridge` 要明确。

### 错误处理

- C 层用 `int` 返回 0 / -1，错误写进 `char *err, size_t errlen`，文案是小写英文短语 + `strerror(errno)`，例：`open %s: %s`。
- ObjC 层面向用户的文案走 `.strings`，不要硬编码中英文；内部 `slim_log` 用英文。
- 失败时清理已分配资源（`unlink` 临时文件、`CFRelease`、`free`），项目里已有写临时文件 + `rename` 的原子写法，配置保存请沿用。

### 日志

统一用 `slim_log("capture full screen: %dx%d", w, h)`。不要把日志写成一句话长句；按「动作: 关键值」的格式，方便 `grep`。日志文件 `~/Library/Logs/Slimshot.log`，超过 1 MB 自动轮转为 `.log.1`。

## 5. 关键不变量（改代码前先看）

### 坐标

这是最容易出 bug 的地方。三种坐标系必须分清：

- `NSScreen.frame`：AppKit 坐标，原点在**主屏左下**，y 向上。
- CoreGraphics 全局坐标：原点在**主屏左上**，y 向下。`SlimScreenGlobalCGRect` 就是做这个翻转的。
- 覆盖层内的 `localRect`：相对某块屏幕的 CG 全局原点。

任何跨屏、Retina、旋转屏的逻辑，都先写出换算注释再动手。像素尺寸用 `display.width * filter.pointPixelScale`，不要假设 2x。

多显示器覆盖层的事故复盘、为什么必须每屏一个窗口、以及回归清单见 [`docs/cross-screen-overlay.md`](docs/cross-screen-overlay.md)。

### 内存

- `CGImageRef` 不归 ARC 管。跨作用域传递时明确所有权：`SlimScreenCapture` 内部 `CGImageRetain`，`dealloc` 里 `CGImageRelease`；临时图用完立刻 `CGImageRelease`。
- `SlimScreenCapture` 同时持有 `CGImageRef` 和 `NSImage`，是为了快照层不重复解码，别为了"省内存"把两者合并。

### 线程

- ScreenCaptureKit 回调在后台队列，**必须** `dispatch_async(dispatch_get_main_queue(), ...)` 再碰 AppKit。
- 任何异步捕获路径都要保证 `_busy` 复位，包括失败分支（见 `SlimCaptureController`）。
- 不要在主线程做图片编码/写盘的重活；`output` 路径要保持可测的短耗时（目标：确认选区到剪贴板 < 50 ms）。

### 配置

- `~/Library/Application Support/Slimshot/config.json` 是**唯一事实源**。设置窗口、菜单、热键都读同一份内存里的 `slim_config_t`，不要在别处再存一份偏好。
- 新增字段需要**同时**改：`config.h` 结构体、`slim_config_defaults`、`load_from_path` 的读取与校验、`save_to_path` 的写回、`tests/config_test.c`。缺一项就算没做完。
- 读取时保持宽容：缺字段用默认值，非法值 clamp 或忽略（参考 `clamp_int`、`valid_format`）。

### 本地化

- 每个面向用户的字符串都要在 `resources/en.lproj/Localizable.strings` 和 `zh-Hans.lproj` 里各有一条，key 用 `模块.用途`（`menu.*`、`settings.*`、`alert.*`、`overlay.*`）。
- 增删 key 时两个文件一起改，不要只改中文。

### 热键

`hotkeys.m` 用 Carbon `RegisterEventHotKey`，所以**不需要辅助功能权限**——这是产品承诺，别换成 `CGEventTap`。键位字符串格式固定为小写 `mod+mod+key`，例：`alt+shift+1`、`cmd+shift+a`。新增修饰键或特殊键时同步更新 `SlimKeyCodeForCharacter` / `SlimKeyCodeForFunctionKey` 与 README 的默认值表格。

### 权限

只用 `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`。不申请辅助功能权限。未授权时的引导路径在 `permissions.m` + `app.m`，菜单项 `menu.permission…` 必须始终可用（即使未授权也能跳系统设置）。

## 6. 签名与分发（改动高风险区）

- 默认 ad-hoc 签名**只用于开发**。ad-hoc 的 cdhash 每次重建都会变，屏幕录制权限会失效。
- 正式构建用稳定自签名身份：

```bash
./scripts/create-dev-cert.sh
CODESIGN_IDENTITY="Slimshot Dev" \
CODESIGN_KEYCHAIN="$HOME/Library/Keychains/slimshot-dev.keychain-db" \
make
```

- 私钥、Sparkle EdDSA 私钥只放 GitHub Actions Secrets，**永远不进仓库**（`.gitignore` 已挡 `*.pem *.p12 *.key *.cer *.mobileprovision`）。
- 发布流程复刻 downvid：`ditto -c -k` 打包、SHA-256 校验、独立脚本等待退出 → 备份 → 替换 → `xattr -dr com.apple.quarantine` → 重签 → 失败回滚。改这段脚本要同时验证成功和回滚两条路径。

## 7. 测试

`tests/config_test.c` 是纯 C 测试，覆盖 defaults、读写往返、非法值容错、命名模板。新增 core 逻辑就加断言，不要为了测试往 bridge 里加可测性钩子。

UI 和 SCK 行为目前靠手工 + 环境变量验证。如果以后要加自动化，优先给 `naming` / `config` / `paths` 这类纯函数补测试，而不是搞 UI 自动化框架。

## 8. 提交与文档

- 提交信息用英文祈使句，一行主题 + 空行 + 正文说明「为什么」，例：`overlay: clamp selection to frozen snapshot bounds`。
- 一个提交只做一件事；重构和行为变更分开。
- 改了构建方式、目录结构、默认值或用户可见行为，**同一个提交里**更新 `README.md`；改了需求边界更新 `REQUIREMENTS.md`。
- 不要提交 `build/`、`dist/`、`*.o`、`*.d`（已在 `.gitignore`）。

## 9. 明确不做

除非需求文档改了，否则不要主动引入：

- Swift / SwiftPM / Xcode 工程（保持 Makefile + clang）
- 除 cJSON、Sparkle 2 之外的第三方运行时依赖
- `SCStream` 常驻录制（M1 只用 `SCScreenshotManager`）
- 截图历史、图库、云同步、内置标注编辑器
- CLI / URL Scheme / AppleScript 入口（v1 范围外）

## 10. 代理工作流

1. 先定位改动属于 `core` 还是 `bridge`，再确认是否触碰第 5 节的不变量。
2. 需要跨多个文件一致修改的（如新增配置字段、新增本地化 key），一次性列全清单再动手。
3. 改完立刻 `make clean && make && make test`；有编译警告就修掉，不要 `#pragma` 屏蔽。
4. 涉及 UI 的改动，用 `make debug` 或 `SLIMSHOT_CAPTURE_ON_LAUNCH=...` 实际跑一遍再汇报。
5. 汇报时给出：改了哪些文件、为什么、如何验证的、有什么已知限制。不要只说"已完成"。
