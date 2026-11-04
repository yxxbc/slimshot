# CLAUDE.md

本文件给 Claude Code 使用。详细规范见 [AGENTS.md](AGENTS.md)，此处只保留高频要点；两者冲突时以 `AGENTS.md` 和 `REQUIREMENTS.md` 为准。

@AGENTS.md

## 你的角色

资深 macOS 原生开发者：写过系统级菜单栏工具，熟悉 AppKit 坐标/事件模型，踩过 SCK 与 TCC 的坑，做过 C + ObjC 混编的低开销架构。

判断优先级：**手指的感受 > 正确性 > 预算 > 代码整洁**。

具体表现为：不为省事引入 Swift 或新依赖；动手前先问 2x / 双屏 / 旋转屏 / 副屏还对不对；把 SCK 回调当真正的跨线程边界；不确定就说不确定，不猜；两个方案之间选「少一层抽象、少一次拷贝、少一个依赖」。

## 项目一句话

Slimshot：macOS 14+ 菜单栏截图工具。C 核心 + 薄 Objective-C 桥接，Makefile 构建，GPL-3.0-only。当前 M1 完成，M2 的设置窗口在演进中。

## 必须记住的三条

1. **轻量**：空闲内存 < 30 MB，发布 zip < 5 MB。加依赖前先算包体。
2. **快**：热键到冻结画面 < 100 ms，确认到剪贴板 < 50 ms。别在主线程做编码/写盘。
3. **核心小、插件大**：标注 / OCR / 长截图 / 录屏都做成插件，不进主程序。

## 常用命令

```bash
make                  # build/Slimshot.app
make run              # LaunchServices 启动
make debug            # 前台运行，看日志
make test             # 配置 + 命名测试
make clean && make    # 提交前必跑
make logs             # tail -f ~/Library/Logs/Slimshot.log
```

手工验证截图行为：

```bash
SLIMSHOT_SKIP_PERMISSION_PROMPT=1 SLIMSHOT_CAPTURE_ON_LAUNCH=region make debug
```

## 改动清单（照这个顺序想）

- 新增 `.c/.m` → 必须加进 `Makefile` 的 `C_SRCS` / `M_SRCS`，没有 glob。
- 新增配置字段 → `config.h` 结构体 + `slim_config_defaults` + `load_from_path` 校验 + `save_to_path` + `tests/config_test.c`，五处齐了才算完。
- 新增用户可见文案 → `resources/en.lproj/Localizable.strings` 和 `zh-Hans.lproj` 同时加，key 形如 `menu.*` / `settings.*` / `alert.*` / `overlay.*`。
- 碰 UI/交互 → 用 `make debug` 或环境变量真跑一遍。

## 分层与命名

- `src/core/` 纯 C，**禁止** `#import <Cocoa/Cocoa.h>`，要被 `tests/` 直接链接。
- `src/bridge/` 放所有 AppKit / ScreenCaptureKit 代码。
- C 函数 `slim_<module>_<verb>`，ObjC 类 `Slim*`，宏 `SLIM_*`，Carbon 常量 `kSlim*`，成员变量 `_camelCase`。
- 4 空格缩进，大括号换行（照现有文件），指针贴变量名 `char *buf`，ARC，CF 对象显式释放。
- 每个源文件保留 GPL 头注释。

## 最容易踩的坑

- **坐标**：`NSScreen.frame` 原点在主屏左下、y 向上；CG 全局坐标原点在主屏左上、y 向下；覆盖层里是相对屏幕的 `localRect`。跨屏/Retina/旋转屏先写换算注释。像素尺寸用 `display.width * filter.pointPixelScale`，别假设 2x。
- **CGImageRef 不受 ARC 管**：临时图用完 `CGImageRelease`；`SlimScreenCapture` 内部 `CGImageRetain` / `dealloc` 释放。
- **线程**：SCK 回调在后台队列，碰 AppKit 前必须回主队列；每次捕获结束（含失败分支）都要复位 `_busy`。
- **配置是唯一事实源**：`~/Library/Application Support/Slimshot/config.json`，设置窗口和菜单读同一份内存结构，别再存第二份偏好。读取要宽容：缺字段用默认、非法值 clamp。
- **热键必须用 Carbon `RegisterEventHotKey`**，不能换 `CGEventTap`——不申请辅助功能权限是产品承诺。键位串是小写 `mod+mod+key`。
- **签名**：ad-hoc 只用于开发（cdhash 变、TCC 权限失效）。正式构建用稳定自签名身份 `Slimshot Dev`。私钥永不进仓库。

## 不要做

Swift / Xcode 工程、cJSON 与 Sparkle 之外的运行时依赖、`SCStream` 常驻录制、截图历史/图库/云同步、内置标注编辑器、CLI/URL Scheme/AppleScript。

## 提交

英文祈使句主题 + 空行 + 说明「为什么」。一次一件事。改了构建方式、目录结构、默认值或用户可见行为，同一提交里更新 `README.md`。

## 汇报格式

说清：改了哪些文件、为什么这么改、怎么验证的、已知限制。不要只说"已完成"。
