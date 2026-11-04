# Slimshot 需求收敛稿

> 版本：v0.1（需求确认）
> 日期：2026-11-03
> 目标平台：macOS 14+
> 当前状态：M0/M1 已完成；全局热键与跨屏区域截图已提前接入，M2 设置窗口进行中

## 1. 定位与优先级

Slimshot 是一个常驻菜单栏的轻量截图工具，先服务个人日常/开发使用，后续在 GitHub 开源。

优先级从高到低：

1. 框选/窗口交互最顺手
2. 截图速度最快
3. 常驻轻量：空闲内存 < 30MB，安装包 < 5MB
4. 核心小而插件可扩展

v1 明确不做：

- 截图历史/图库管理
- 云同步/团队协作
- 内置标注编辑器（做成插件）
- 滚动长截图/录屏（做成插件）
- CLI、URL Scheme、AppleScript/Shortcuts

## 2. 产品形态

- 菜单栏 App，`LSUIElement=1`，无 Dock 图标
- 独立设置窗口
- 界面跟随系统语言：简体中文 / English，使用 `.strings`
- 全局热键 + JSON 高级配置
- 首次启动引导授予“屏幕录制”权限
- 不申请“辅助功能”权限

## 3. 核心功能

### 3.1 截图模式

| 模式 | 行为 |
| --- | --- |
| 全屏 | 截取光标所在显示器 |
| 窗口 | 所有显示器上高亮窗口，点击截取 |
| 区域 | 按下热键立即冻结显示器；跟随光标模式下冻结所有屏幕，可跨屏框选 |

多显示器默认跟随光标所在屏幕，菜单中可切换其他显示器。跟随光标时区域截图覆盖所有显示器，选区可以跨屏拖动；固定某个显示器时只覆盖该屏。窗口模式始终覆盖所有显示器，点击哪块屏上的窗口就截哪块屏。每块屏幕一个覆盖层窗口，共享同一份全局选区；不假设左右排列，上下、错位、负坐标都支持。Retina 屏按原生像素输出（2x）。

### 3.2 框选交互

- 十字线 + 实时显示选区尺寸/坐标
- 窗口级自动高亮吸附；不做 UI 元素识别，因此不需要辅助功能权限
- 截前可拖动选区、拉边调整尺寸
- v1 不做放大镜和像素级微调
- 冻结画面方案：跟随光标时先抓所有显示器，固定显示器时只抓该屏；框选和预览都在冻结画面上完成，避免二次抓屏延迟
- 跨屏输出按各屏原生分辨率裁剪并拼接；屏幕之间的空隙填黑

### 3.3 截图后

- 复制到剪贴板（默认开启）
- 自动保存到 `~/Pictures/Screenshots`，时间戳命名（默认开启）
- 目录和命名模板可在 JSON/设置窗口修改
- 右下角浮动缩略图：可拖动、点击操作、自动消失
- 输出格式：PNG / JPEG / HEIC / TIFF，默认 PNG
- JPEG/HEIC 质量可配置，默认 0.9
- 默认不包含鼠标指针
- 窗口截图 v1 不含窗口阴影（ScreenCaptureKit 不直接提供，后续可做合成）

### 3.4 设置窗口

独立设置窗口，建议分组：

- 通用：开机启动、语言、缩略图开关
- 截图：模式、显示器、是否包含指针
- 输出：格式、质量、保存目录、命名模板、剪贴板开关
- 热键：三种模式的全局热键
- 插件：插件目录、启用/禁用、超时
- 关于：版本、更新、开源地址

JSON 是配置的唯一事实源，设置窗口读写同一份配置。

### 3.5 权限与引导

- 使用 `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess` 检查并请求屏幕录制权限
- 未授权时在菜单栏和设置窗口给出明确引导，提供“打开系统设置”按钮
- 不申请辅助功能权限

## 4. 插件系统

### 4.1 机制

- 独立进程 + JSON over stdin/stdout
- 插件可以用任意语言实现
- 进程崩溃不影响主程序
- 主程序负责超时、退出码、stderr 捕获和错误提示
- 不要求插件签名；插件是用户主动安装的可执行代码，文档中说明信任模型

### 4.2 插件类型

| 类型 | 用途 | 输入 | 输出 |
| --- | --- | --- | --- |
| `post-process` | 对截图做后处理（OCR、标注、上传等） | 图片路径 + 元数据 | 结果 JSON + 可选输出图片 |
| `standalone` | 自己抓屏/自己弹 UI（滚动长截图、录屏/GIF） | 上下文 JSON | 结果 JSON |

### 4.3 目录与清单

插件目录：

- 内置：`Slimshot.app/Contents/Resources/Plugins/<id>/`
- 用户：`~/Library/Application Support/Slimshot/Plugins/<id>/`

每个插件包含 `manifest.json` 和可执行文件：

```json
{
  "id": "ocr",
  "name": "OCR",
  "version": "0.1.0",
  "type": "post-process",
  "exec": "ocr",
  "timeout_ms": 15000
}
```

### 4.4 请求/响应

请求示例：

```json
{
  "protocol": 1,
  "type": "post-process",
  "plugin_id": "ocr",
  "image_path": "/tmp/slimshot-20261103-215600.png",
  "output_dir": "/tmp",
  "width": 2560,
  "height": 1600,
  "scale": 2.0,
  "source": "region",
  "created_at": "2026-11-03T21:56:00+08:00"
}
```

响应示例：

```json
{
  "ok": true,
  "message": "recognized 42 chars",
  "output_path": null,
  "clipboard_text": "识别出的文字"
}
```

约定：

- 图片用文件路径传递，不用 base64，避免大图占内存
- 主程序写 stdin 后关闭；插件通过 stdout 返回单行 JSON
- 非 0 退出码、超时、非法 JSON 均视为失败
- 插件 stderr 写入日志，便于排查

### 4.5 v1 交付

- 插件宿主 + 协议 + 插件菜单
- 1 个参考插件：OCR（用 Vision，验证 post-process 协议）
- 标注编辑器、滚动长截图、录屏/GIF、上传/分享后续迭代

## 5. 技术架构

### 5.1 语言与框架

- C 核心 + 薄 Objective-C 桥接
- ScreenCaptureKit：`SCScreenshotManager`（macOS 14+），不引入 SCStream
- AppKit：菜单栏、冻结框选覆盖层、缩略图、设置窗口
- ImageIO：PNG/JPEG/HEIC/TIFF 编码
- Carbon `RegisterEventHotKey`：全局热键（C API，不需要辅助功能权限）
- cJSON：配置和插件协议解析（允许的轻量第三方依赖）
- Sparkle 2：自动更新（ObjC framework）

### 5.2 目录草案

```text
slimshot/
├── Makefile
├── REQUIREMENTS.md
├── resources/
│   ├── Info.plist
│   ├── en.lproj/Localizable.strings
│   └── zh-Hans.lproj/Localizable.strings
├── src/
│   ├── main.m
│   ├── core/
│   │   ├── config.c/.h
│   │   ├── plugin.c/.h
│   │   ├── naming.c/.h
│   │   └── log.c/.h
│   ├── bridge/
│   │   ├── capture.h
│   │   ├── capture.m
│   │   ├── app.m
│   │   ├── overlay.m
│   │   ├── settings.m
│   │   ├── thumbnail.m
│   │   ├── permissions.m
│   │   └── updater.m
│   └── plugins/ocr/
│       └── main.m
├── scripts/
│   ├── build.sh
│   ├── sign.sh
│   ├── install.command
│   └── generate_appcast.sh
└── docs/
```

### 5.3 关键流程

1. 热键触发，判断当前显示器
2. 区域/全屏：`SCScreenshotManager` 抓取显示器；区域模式把图放进无边框覆盖层
3. 窗口模式：枚举 `SCShareableContent.windows`，覆盖层按鼠标位置高亮窗口
4. 用户确认后裁剪/抓取窗口，得到 `CGImageRef`
5. 编码并写入剪贴板/文件
6. 显示浮动缩略图
7. 若配置了插件，按需执行后处理插件

线程模型：SCK 异步回调在后台队列，UI 操作回主线程；用完成信号/超时避免阻塞主线程。

## 6. 分发、签名与更新

### 6.1 发布方式

- 许可证：GPL-3.0-only（GPLv3）
- 源码开源，GitHub Releases 发布
- 产物为 `Slimshot.app` 的 zip（可选 DMG）
- 首次安装提供 `install.command`，DMG 内附“修复隔离属性.command”

### 6.2 清理隔离：复用 downvid 的流程

downvid 的 macOS 清理/更新流程已经过大量用户验证，Slimshot 直接复用同一套机制：

1. 首次启动：应用检测并移除自身 bundle 的 `com.apple.quarantine`
2. 安装包内附 `install.command`：
   - `xattr -dr com.apple.quarantine Slimshot.app`
   - 拷贝到 `/Applications`
   - `codesign --verify --deep --strict Slimshot.app`
3. 应用内更新：
   - 下载 zip → 校验 SHA-256 → `ditto -x -k` 解压到临时目录
   - 对解压后的 `.app` 先 `xattr -dr com.apple.quarantine`
   - 用稳定签名身份重签
   - 启动独立 shell 脚本：等待主进程退出 → 备份旧 `.app` → `ditto` 新包 → 清隔离 → 重签 → 成功则重启，失败则回滚
4. 发布前 CI 执行 `codesign --verify --deep --strict`

downvid 的实现可参考 `app/internal/update/install_mac.go`：整个 `.app` 替换、独立脚本等待退出、备份/回滚、清隔离、重签、重启。

### 6.3 签名策略：稳定自签名，不是纯 ad-hoc

downvid 使用 `codesign --force --deep --sign -`（ad-hoc），因为它不需要屏幕录制权限。Slimshot 不同：

- ad-hoc 的 designated requirement 是 cdhash，每次重建/更新都会变
- TCC 屏幕录制权限绑定 code requirement；更新后会被当成新 App，用户必须重新授权
- Sparkle 的更新校验也依赖代码签名连续性

因此：

- 生成一次稳定的自签名证书（如 `Slimshot Dev`），所有版本用同一身份签名
- 仍然不做 Apple Developer ID 公证，不交 $99
- 开发期也尽量用同一证书；纯 ad-hoc 只用于临时构建
- 证书私钥和 Sparkle EdDSA 私钥放 GitHub Actions Secrets

### 6.4 Sparkle 2

- appcast 用 EdDSA 签名
- `generate_appcast` 生成 appcast 和增量更新
- `SUFeedURL` 指向 GitHub Releases / GitHub Pages 上的 appcast
- 更新包与 appcast 的签名公钥写入 Info.plist

### 6.5 用户侧说明

首次安装需要运行 `install.command`，或在“系统设置 → 隐私与安全性”中放行；这是免公证的代价。安装后屏幕录制权限只需授权一次（前提是签名身份稳定）。

## 7. 性能目标与验证

| 指标 | 目标 | 验证方式 |
| --- | --- | --- |
| 空闲内存 | < 30MB | `footprint`、Activity Monitor |
| 安装包 | < 5MB | `du -sh`、发布 zip |
| 热键到冻结画面 | < 100ms | 打点日志/Instruments |
| 确认选区到剪贴板 | < 50ms | 打点日志 |
| 空闲 CPU | 接近 0 | Activity Monitor |

注意：AppKit + Sparkle 会占基础内存和包体，目标需要在 M1/M4 实测后校准；如果超标，优先裁 Sparkle 资源、延迟加载设置窗口、避免轮询。

## 8. v1 范围与里程碑

| 阶段 | 交付 |
| --- | --- |
| M0 | Makefile、App bundle、Info.plist、菜单栏、JSON 配置、日志、权限检查、签名脚本 |
| M1 | 全屏/窗口/区域冻结框选、窗口高亮、多屏/Retina、跨屏区域框选、剪贴板、保存、缩略图 |
| M2 | 设置窗口（Carbon 全局热键已完成）、配置读写、格式/质量/路径 |
| M3 | 插件宿主、JSON 协议、OCR 参考插件、插件菜单 |
| M4 | Sparkle 2、appcast、downvid 式更新脚本（等待退出/备份/回滚/清隔离/重签）、install.command、GitHub Actions 发布 |
| M5+ | 标注编辑器、滚动长截图、录屏/GIF、上传/分享 |

v1 的“完成”定义：M0-M4 全部可用，能日常替代系统截图。

## 9. 风险与待确认

### 风险

- 纯 ad-hoc 签名会导致 TCC 权限在每次重建后失效；必须使用稳定自签名证书
- Sparkle + 5MB 包体目标可能冲突，需要实测后取舍
- AppKit 菜单栏 App 的空闲内存可能接近或超过 30MB，需要实测
- macOS 15+ 对屏幕录制权限有周期性提醒，需要在引导中说明
- 冻结画面与窗口列表可能短暂不一致，窗口模式需要在覆盖前刷新窗口信息
- ScreenCaptureKit 窗口截图不含阴影，v1 接受这个限制
- 多显示器、旋转屏、不同缩放比例下的坐标换算需要专门测试
- 全局热键可能和用户现有工具冲突，需要冲突提示
- 插件是任意代码执行，信任模型必须在文档中写清楚
- GPL-3.0-only 要求分发对应源码；插件通过独立进程 + JSON 通信，建议在文档中明确插件的授权边界（插件可独立授权）

### 默认假设（待你确认或纠正）

- App 名称：Slimshot
- Bundle ID：`com.slimshot.app`
- 许可证：GPL-3.0-only（GPLv3）
- 参考插件：OCR
- 默认热键：`⌥⇧1` 全屏、`⌥⇧2` 窗口、`⌘⇧A` 区域
- 剪贴板默认开启，自动保存默认开启
- 文件名：`Slimshot-YYYY-MM-DD_HH-mm-ss.png`
- 缩略图 3 秒后自动消失
- JPEG/HEIC 质量 0.9
- 截图不含鼠标指针
- 窗口截图不含阴影
- 日志：`~/Library/Logs/Slimshot.log`，按大小轮转
