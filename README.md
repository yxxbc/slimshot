<p align="center">
  <img src="resources/icon/Slimshot-256.png" width="128" alt="Slimshot">
</p>

# Slimshot

轻量级 macOS 菜单栏截图工具。核心用 C，ScreenCaptureKit / AppKit 放在一层很薄的 Objective-C 桥接里。

> 当前状态：**M1 + 全局热键 + 跨屏区域截图**。全屏 / 窗口 / 区域截图、冻结框选、剪贴板、自动保存、浮动缩略图已接入。设置窗口已支持权限、格式、JPEG/HEIC 质量、缩略图时长和鼠标指针；插件系统仍在 M3。

## 环境要求

- macOS 14+
- Xcode Command Line Tools（`xcrun`、`clang`、`codesign`）
- 不需要 Apple Developer 账号

## 构建

```bash
make            # 生成 build/Slimshot.app
make run        # 通过 LaunchServices 启动
make debug      # 在终端里直接运行，能看到日志
make test       # 配置读写、命名模板测试
make clean
```

调试用环境变量：

```bash
# 跳过启动时的权限弹窗
SLIMSHOT_SKIP_PERMISSION_PROMPT=1 ./build/Slimshot.app/Contents/MacOS/Slimshot

# 启动后直接打开设置窗口
SLIMSHOT_OPEN_SETTINGS=1 ./build/Slimshot.app/Contents/MacOS/Slimshot

# 启动后自动触发一次截图，用于测试：full | window | region
SLIMSHOT_CAPTURE_ON_LAUNCH=full ./build/Slimshot.app/Contents/MacOS/Slimshot
```

M1 实测（arm64）：bundle 约 264 KB，zip 约 96 KB，空闲 `phys_footprint` 约 13 MB。`ps` 的 RSS 会包含共享框架，不等于真实占用；请用 `footprint -p <pid>` 或 `vmmap -summary <pid>` 测量。当前构建是本地架构，M4 发布前再做 universal binary。

## 全局热键

默认：

- 全屏：`⌥⇧1`
- 窗口：`⌥⇧2`
- 区域：`⌘⇧A`

在 `config.json` 的 `hotkey_fullscreen` / `hotkey_window` / `hotkey_region` 里修改，重启生效。使用 Carbon 注册，不需要辅助功能权限。

如果热键被其他 App 占用，日志里会记录注册失败；换一个组合即可。

## 截图

菜单栏图标：

- **Capture Full Screen**：截取当前显示器
- **Capture Window**：在所有屏幕上高亮窗口，点击任意窗口截图
- **Capture Region**：冻结显示器后框选；跟随光标模式下覆盖所有屏幕，可以跨屏拖动
- **Capture Display**：影响全屏和固定区域；窗口模式总是覆盖所有屏幕

区域模式操作：

- 拖动框选，跟随光标模式下选区可以跨屏幕
- 悬停窗口会高亮，单击窗口直接截图
- 框选后可拖动选区、拉边/拉角调整
- 选中后选区旁出现尺寸和「✓ 截图 / × 取消」操作条
- `Enter` 或双击也可以确认，`Esc` 或右键取消
- 顶部拖动提示只在未选中时显示

最终输出会按各块屏幕的原生分辨率裁剪并拼接；跨屏选区之间的空隙会填黑。

每块屏幕一个覆盖层窗口，共享同一份全局选区；不假设左右排列，上下、错位、负坐标都支持。

窗口模式：点击高亮窗口直接截图。

## 输出

- 复制到剪贴板（PNG + TIFF）
- 自动保存到 `~/Pictures/Screenshots`，时间戳命名
- 右下角浮动缩略图：可拖动，点击打开保存的文件，默认 3 秒后消失
- 格式：PNG / JPEG / HEIC / TIFF
- 格式、JPEG/HEIC 质量、缩略图时长、是否包含指针可在设置窗口修改
- 目录、命名模板在 `config.json` 中配置

配置路径：`~/Library/Application Support/Slimshot/config.json`
日志路径：`~/Library/Logs/Slimshot.log`

## 权限

Slimshot 需要“屏幕录制”权限。首次启动会弹窗引导；也可以从菜单栏打开“屏幕录制权限…”跳转到系统设置。

不需要辅助功能权限。

如果重新构建时换了签名身份，macOS 可能把新版本当成新 App，要求重新授权屏幕录制。开发期重新编译后如果权限失效，重新授权一次即可。

如果系统设置里已经勾选 Slimshot、但 App 仍提示未授权，可以重置该 App 的权限后重新授权：

```bash
tccutil reset ScreenCapture com.slimshot.app
```

然后重启 Slimshot，按提示重新开启屏幕录制。

## 签名

默认使用 ad-hoc 签名，方便开发，但每次重建后 cdhash 会变化，屏幕录制权限可能需要重新授权。

正式构建请使用稳定的自签名证书：

```bash
./scripts/create-dev-cert.sh

make clean
CODESIGN_IDENTITY="Slimshot Dev" \
CODESIGN_KEYCHAIN="$HOME/Library/Keychains/slimshot-dev.keychain-db" \
make
```

自签名证书不经过 Apple 公证，Gatekeeper 仍会拦截首次打开；用 `install.command` 清除 quarantine 即可。

## 打包与安装

```bash
make dist
```

产物：

- `dist/Slimshot-0.1.0.zip`
- `dist/Slimshot-0.1.0.zip.sha256`

zip 内包含 `Slimshot.app`、`install.command`、`LICENSE` 和本 README。解压后双击 `install.command`，脚本会：

1. 清除 `com.apple.quarantine`
2. 拷贝到 `/Applications`
3. 校验代码签名
4. 启动 Slimshot

如果 Gatekeeper 拦截 `install.command` 本身，右键 → 打开。

## 目录结构

```text
src/core/        C 核心：配置、命名、路径、日志
src/bridge/      ObjC 桥接：菜单栏、设置、SCK 截图、框选层、输出、缩略图
src/vendor/      cJSON 1.7.18（MIT）
resources/       Info.plist、中英文 strings、icon（PNG + icns）
tests/           配置、命名测试
scripts/         构建、签名、证书、打包、安装
docs/            设计笔记：覆盖层坐标系、设置与关于界面布局
```

## 设计文档

- [跨屏覆盖层与坐标系](docs/cross-screen-overlay.md)：多显示器、Retina、负坐标下的覆盖层设计与事故复盘
- [设置与关于界面布局](docs/ui-layout.md)：间距、对齐、窗口结构和控件顺序

## 路线图

- M1：全屏 / 窗口 / 区域冻结框选、窗口高亮、剪贴板、保存、缩略图
- M2：完整设置窗口（Carbon 全局热键已完成）
- M3：插件宿主 + JSON 协议 + OCR 参考插件
- M4：Sparkle 2、appcast、downvid 式更新脚本、GitHub Actions 发布

## 许可证

GPL-3.0-only。见 [LICENSE](LICENSE)。
