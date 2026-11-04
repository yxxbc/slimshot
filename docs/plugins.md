# 插件

Slimshot 的插件是**独立进程**：主程序把请求 JSON 写到 stdin，插件把响应 JSON 写到 stdout。插件崩溃、超时或输出非法 JSON 都不会影响主程序。插件可以用任何语言实现。

> 涉及文件：`src/core/plugin.c`（发现与进程调度）、`src/bridge/plugins.m`（菜单与结果处理）、`src/plugins/ocr/`（参考插件）

## 目录

- 内置：`Slimshot.app/Contents/Resources/Plugins/<id>/`
- 用户：`~/Library/Application Support/Slimshot/Plugins/<id>/`

每个插件一个目录，必须包含 `manifest.json` 和清单里 `exec` 指向的可执行文件。用户插件与内置插件 `id` 相同时，用户插件覆盖内置插件。

## manifest.json

```json
{
  "id": "ocr",
  "name": "OCR",
  "version": "0.1.0",
  "icon": "text.viewfinder",
  "type": "post-process",
  "exec": "ocr",
  "timeout_ms": 15000
}
```

| 字段 | 说明 |
| --- | --- |
| `id` | 小写/大写字母、数字、`.`、`_`、`-`，最长 63 字符 |
| `name` | 菜单显示名 |
| `version` | 插件版本，可省略，默认 `0.0.0` |
| `icon` | 可选 SF Symbol 名称；默认 `puzzlepiece.extension` |
| `type` | `post-process` 或 `standalone` |
| `exec` | 相对插件目录的可执行文件路径；不允许绝对路径或 `..` |
| `timeout_ms` | 1000–600000，默认 15000；带 UI 的编辑器可设 600000 |

发现阶段会检查 `exec` 存在且可执行；非法清单会跳过并写日志。

## 请求

主程序在运行插件时写入一行 JSON：

```json
{
  "protocol": 1,
  "type": "post-process",
  "plugin_id": "ocr",
  "image_path": "/Users/me/Pictures/Screenshots/Slimshot-2026-11-04_14-00-00.png",
  "output_dir": "/tmp/",
  "width": 2560,
  "height": 1600,
  "scale": 2.0,
  "source": "region",
  "created_at": "2026-11-04T14:00:00Z"
}
```

- `image_path` 是最近一次截图的文件路径。自动保存开启时是保存的文件；关闭时会写一份临时 PNG 到 `$TMPDIR/Slimshot/last-capture.png`。
- `width`/`height` 是像素尺寸，`scale` 是屏幕缩放提示。
- `source` 是 `full`、`window`、`region` 之一。
- `standalone` 插件可能没有截图，`image_path` 为空字符串。

## 响应

插件向 stdout 输出**单行 JSON**：

```json
{
  "ok": true,
  "message": "recognized 42 chars",
  "output_path": null,
  "clipboard_text": "识别出的文字"
}
```

- `ok`：是否成功。
- `message`：给用户看的简短结果，主程序会显示在提示框里。
- `output_path`：插件生成的图片路径，可为 `null`；当前版本只写日志，不自动打开。
- `clipboard_text`：非空时主程序写入系统剪贴板。

非 0 退出码、超时、非法 JSON 都视为失败；stderr 会写入日志并尽量显示给用户。

## 运行与限制

- 区域框选后的操作条是一条**垂直图标轨**：最多直接显示 4 个 `post-process` 插件，更多插件进入「…」菜单；插件按钮带 tooltip，数字键 `1`–`9` 可直接运行。`Return` 截图，`Esc` 取消。
- 全屏/窗口截图后的浮动缩略图底部也显示插件图标（最多 4 个 + 溢出）；有插件时缩略图至少停留 8 秒。
- 菜单栏「插件」子菜单在打开时重新扫描目录，显示全部插件。`post-process` 插件在没有截图时置灰；`standalone` 插件随时可运行。
- 主程序最多读取 8 MB stdout、512 KB stderr；超时后杀掉整个进程组。
- 带 UI 的插件（如 Editor）会打开自己的窗口；主程序在后台等待它的 JSON，超时上限 10 分钟。
- 插件不签名、不沙箱；插件是用户主动安装的可执行代码。只运行你信任的插件。
- 当前没有启用/禁用开关、没有插件参数 UI、没有 standalone 参考插件；这些留给后续迭代。

## 参考插件

### OCR

`src/plugins/ocr/` 使用 Vision：

- 读取 `image_path`，用 `VNRecognizeTextRequest` 做准确识别，语言 `zh-Hans` + `en-US`。
- 按 XY-cut 的阅读顺序（先分栏、再分块、最后从上到下）拼接文本。
- 把文本放进 `clipboard_text`，主程序复制到剪贴板并提示字符数。

构建时会编译到 `Slimshot.app/Contents/Resources/Plugins/ocr/`。

### Editor

`src/plugins/editor/` 是一个带 UI 的 `post-process` 插件：

- 打开独立 AppKit 窗口，拖拽绘制红色矩形标注；支持撤销。
- 「保存并复制」把标注后的 PNG 写入 `output_dir`，同时复制 PNG/TIFF 到剪贴板，再返回 `output_path` 和结果 JSON。
- `timeout_ms` 设为 600000，允许用户慢慢编辑；关闭窗口视为取消。
- 目前只有矩形工具，没有箭头、文字、马赛克；这些留给后续迭代。

构建时会编译到 `Slimshot.app/Contents/Resources/Plugins/editor/`。

## 测试

```bash
make test   # 包含 plugin_test：发现、成功、超时、非 0 退出、非法清单
```

手工调试：

```bash
printf '{"image_path":"/path/to/shot.png"}\n' | \
  build/Slimshot.app/Contents/Resources/Plugins/ocr/ocr
```

用户插件调试时，把目录放到 `~/Library/Application Support/Slimshot/Plugins/<id>/`，再从菜单运行。
