# 跨屏覆盖层与坐标系

> 适用版本：M1 多显示器修复之后（2026-11）
> 涉及文件：`src/bridge/overlay_controller.m`、`overlay_view.m`、`overlay_windows.m`、`capture.m`、`capture_composite.m`、`screen_geometry.m`
> 改这块代码之前，先读完本文并跑一遍第 6 节的回归清单。

## 0. 结论先行

1. **一个屏幕一个覆盖层窗口**。不要让一个 `NSWindow` 横跨两块屏去接收鼠标事件。
2. 跨屏选区的唯一语义是 **CG 全局坐标**；每个覆盖视图只保存自己屏幕的 `localRect` 副本。
3. 窗口命中使用 **CGWindowList 的原生 `kCGWindowBounds`**；不要用 `NSScreen` 再硬转一次。
4. 鼠标在哪块屏用 `CGEventGetLocation` + `CGGetDisplaysWithPoint` + `NSScreenNumber` 匹配；`NSEvent.mouseLocation` 只作兜底。
5. 不假设 2x、不假设左右排列、不假设副屏坐标为正数。

## 1. 三种坐标系

| 坐标系 | 原点 | y 方向 | 典型来源 |
| --- | --- | --- | --- |
| AppKit 屏幕坐标 | 主屏左下角 | 向上 | `NSScreen.frame`、`NSEvent.mouseLocation` |
| CG 全局坐标 | 主屏左上角 | 向下 | `CGWindowList` 的 `kCGWindowBounds`、`CGEventGetLocation`、`SCDisplay` |
| 覆盖层 local 坐标 | 该屏的 CG 全局原点 | 向下（flipped view） | `locationInWindow` 经 `convertPoint:` |

换算公式：

```objc
// 点：AppKit -> CG
cgY = mainHeight - nsY;

// 矩形：AppKit -> CG
cgY = mainHeight - (nsY + height);

// local <-> CG
local  = global - screenGlobalRect.origin;
global = local  + screenGlobalRect.origin;
```

`mainHeight` 必须是**主屏**（带菜单栏的那块，`[NSScreen screens].firstObject`）的 frame 高度，不是当前屏幕的高度。

本机实测布局（两块屏，上下排列，缩放不同）：

```text
AppKit 坐标（主屏左下为原点，y 向上）
  内屏 frame = (0, 0,    1470, 956)    // 2x，原生 2940x1912
  外屏 frame = (0, 956,  1920, 1080)   // 1x

CG 全局坐标（主屏左上为原点，y 向下）
  内屏 = (0, 0,      1470, 956)
  外屏 = (0, -1080,  1920, 1080)       // 注意 y 是负数
```

外屏在上、内屏在下，所以外屏的 CG y 是负的。“副屏坐标一定为正”是错误直觉。

## 2. 事故：一个窗口跨两块屏

2026-11-03/04 的真实故障：

- 鼠标移到外屏，高亮和截图却落到内屏；
- 跟随鼠标模式跨屏框选时，拖到另一块屏就变成普通光标，选区断开；
- 截图工具栏显示 `(393, 1104)`、`2542×1188 px`，把内屏的 2x 缩放串到了外屏选区上。

当时的实现是一个覆盖所有屏幕的联合窗口。日志能把问题钉死：

```text
# 联合窗口（错误）
[00:42:54] overlay show: window=(0,0 1920x2036) view=(0,0 1920x2036) reference=(0,-1080 1920x2036)
[00:42:58] window hit: local=(957,1712) global=(957,632) id=18441 owner=kitty
```

用户实际点的是外屏。外屏在窗口 local 空间里的 y 只能在 `0...1080`，但事件给出的 local y 是 `1712`，比外屏高度还多 632 点，于是被解释成内屏位置；换算成 CG 全局后落到 `y=632`，命中内屏 kitty。偏移是整屏量级的。

同一个联合窗口，外屏另一处点击也曾碰巧正确：

```text
[00:31:32] overlay show: window=(0,0 1920x2036) reference=(0,-1080 1920x2036)
[00:31:55] window hit: local=(95,988) global=(95,-92) id=66311 owner=Google Chrome
```

这说明问题不是“每次都错”，而是窗口横跨两块屏后 local 坐标空间不稳定。对交互工具来说，偶尔错和一直错一样不可接受。

对照单屏覆盖层（外屏固定模式），同样的外屏点击是正确的：

```text
# 单屏覆盖层（正确）
[00:42:42] window hit: local=(590,294) global=(590,-786) id=66311 owner=Google Chrome
```

结论：

- 不是 `CGWindowList` 的 rect 错了；
- 不是 `displayID` 匹配不到 `SCDisplay`；
- 是**跨屏窗口自身的 local 坐标空间不可靠**。窗口横跨两块缩放/位置不同的屏幕时，`locationInWindow` 不再等于“该屏内坐标 - 屏幕原点”，事件会被套进另一个屏幕的坐标空间，产生整屏高度的偏移。

联合窗口还有一个次生问题：覆盖视图的 `displayScale` 只能取一个值。外屏是 1x，内屏是 2x，工具栏的像素尺寸就会按错误的 scale 计算。

因此修复方向不是继续修联合窗口的换算，而是**从根上取消跨屏窗口**。

## 3. 现在的结构：每屏一个覆盖层

```text
SlimOverlayController
├── SlimOverlayWindow 0 / SlimOverlayView 0   ← 内屏
│     referenceCg   = (0, 0, 1470, 956)
│     displayScale  = 2.0
│     selectionBounds = 所有屏幕并集 - referenceCg.origin
├── SlimOverlayWindow 1 / SlimOverlayView 1   ← 外屏
│     referenceCg   = (0, -1080, 1920, 1080)
│     displayScale  = 1.0
│     selectionBounds = 所有屏幕并集 - referenceCg.origin
└── 共享数据
      captures[]  每屏一张冻结图
      windows[]   全部窗口，统一存 CG 全局 rect
```

关键点：

### 3.1 每个视图只认自己的 reference

`SlimScreenGlobalCGRect(screen, mainHeight)` 把 `NSScreen.frame` 翻成 CG 全局 rect，作为该视图的 `referenceCg`。视图内所有本地坐标都相对它：

```objc
global = local + _referenceCg.origin;
local  = global - _referenceCg.origin;
```

窗口高亮、hit-test、选区绘制都走这一条路径，不再有“联合视图原点”这个概念。

### 3.2 全局选区由发起视图广播

选区变更时，发起视图把自己的 local rect 换成全局，再推给所有视图：

```objc
CGRect global = [view selectionGlobalRect];
for (SlimOverlayView *other in _overlayViews) {
    CGRect ref = [other referenceCg];
    NSRect local = NSMakeRect(global.origin.x - ref.origin.x,
                              global.origin.y - ref.origin.y,
                              global.size.width, global.size.height);
    [other setSelectionRect:local];
}
```

确认时方向相反，并且**必须用当前这个视图的 reference 转换**，因为完成动作的视图不一定是起拖的视图：

```objc
CGRect ref = [view referenceCg];
CGRect selectionGlobal = CGRectMake(rect.origin.x + ref.origin.x,
                                    rect.origin.y + ref.origin.y,
                                    rect.size.width, rect.size.height);
```

### 3.3 跨屏拖动靠起始窗口的隐式鼠标抓取

用户在 A 屏按下后拖到 B 屏，AppKit 会持续把 `mouseDragged`/`mouseUp` 投给 A 屏的窗口，B 屏视图只负责重绘。因此：

- 起拖视图的 local 坐标可以超出自己的屏幕范围；
- `_selectionBounds` 是**所有屏幕的并集**，不是当前屏幕的 bounds，所以选区不被屏幕边界截断；
- B 屏视图通过 3.2 的广播看到同一份全局选区。

不要在每个视图里用 `self.bounds` 去 clamp 选区，否则跨屏拖动会被截断。

### 3.4 工具栏和提示只出现一次

- 工具栏放在**包含选区原点**的屏幕上；原点正好在边界时，退化为“与选区交集面积最大的屏幕”。
- 提示只放在起拖屏幕。
- 这样不会出现两块屏各画一个工具栏，也不会出现鼠标在 B 屏却去点 A 屏工具栏的命中问题。

### 3.5 窗口命中统一用 CG 全局坐标

`SlimBuildWindowInfos` 从 `CGWindowListCopyWindowInfo` 拿原生 `kCGWindowBounds`，存进 `SlimWindowInfo.globalRect`，并用 `SCWindow.windowID` 交叉确认窗口仍然存在。命中时把视图 local 点换成 CG 全局点：

```objc
NSPoint global = NSMakePoint(point.x + _referenceCg.origin.x,
                             point.y + _referenceCg.origin.y);
for (SlimWindowInfo *info in _windows) {
    if (NSPointInRect(global, info.globalRect)) {
        return info;
    }
}
```

`_windows` 的顺序来自 CGWindowList 的从前到后，所以重叠窗口会命中视觉上最上面的那个。

### 3.6 跟随鼠标时如何找屏幕

```objc
CGEventRef event = CGEventCreate(NULL);
CGPoint point = CGEventGetLocation(event);   // CG 全局坐标
CFRelease(event);

CGDirectDisplayID displayID = kCGNullDirectDisplay;
uint32_t count = 0;
CGGetDisplaysWithPoint(point, 1, &displayID, &count);
NSScreen *screen = [self screenForDisplayID:displayID];
```

匹配顺序：

1. `CGEventGetLocation` + `CGGetDisplaysWithPoint` + `NSScreenNumber`；
2. 失败则 `NSEvent.mouseLocation` + `NSScreen.frame`；
3. 再失败才回退主屏，并写日志。

不要只用 `NSEvent.mouseLocation`。它和 `NSScreen.frame` 同属 AppKit 坐标，鼠标在负坐标的副屏上时容易和 CG 空间混用。

## 4. 输出合成：按各屏原生分辨率裁剪

冻结图是每屏原生像素，不是统一的 2x。合成逻辑：

1. 用 `CGImageGetWidth / screenCg.size.width` 算出每块屏实际的像素/点比例；
2. 取所有命中屏中**最大**的 scale 作为输出 scale（混合 DPI 时 1x 区域会被放大到 2x）；
3. 每块屏按与选区的交集裁剪；
4. 贴到 bitmap context 时做一次 y 翻转：`dy` 是选区内的偏移，目标 y 为 `outputHeight - dy - height`；
5. 屏幕之间没有覆盖到的区域填黑；
6. 只有一块屏命中时走快路径，直接 `CGImageCreateWithImageInRect`，不建上下文。

不要假设 `display.width * 2`，也不要把所有屏都缩放到主屏的 scale。

## 5. 验证记录

### 5.1 旧实现（联合窗口）

```text
[00:42:54] overlay show: window=(0,0 1920x2036) reference=(0,-1080 1920x2036)
[00:42:58] window hit: local=(957,1712) global=(957,632) owner=kitty
```

外屏点击 → 内屏窗口，local y 多出 1080。

### 5.2 新实现（每屏一个窗口）

离屏 harness 直接链接 `overlay.m`，用合成 `NSEvent` 复现外屏起拖、拖进内屏、回车确认：

```text
start reference=(0,-1080 1920x1080)     # 外屏
other reference=(0,0 1470x956)          # 内屏
expected global=(100,-980 635x1458)
captured global=(100,-980 635x1458)     ✅
expected other local=(100,-980 635x1458)
actual   other local=(100,-980 635x1458) ✅
PASS: cross-screen drag propagated in CG global coordinates
```

同一份选区在内屏视图的本地副本也完全一致，工具栏归属屏幕正确。

真机确认：外屏起拖跨到内屏成功；“跟随鼠标”下点击外屏窗口截到的是外屏窗口。

### 5.3 日志检查点

启动覆盖层后按屏打印：

```text
overlay screen 0: window=(0,0 1470x956) view=(0,0 1470x956) reference=(0,0 1470x956)
overlay screen 1: window=(0,956 1920x1080) view=(0,0 1920x1080) reference=(0,-1080 1920x1080)
```

外屏点击的 `window hit` 应该是：

```text
window hit: local=(..., 小于1080) global=(..., 负数) owner=...
```

如果 `local` 的 y 又出现整屏高度的偏移，说明又退回了跨屏窗口或错误的 reference。

## 6. 回归清单

改覆盖层/坐标系后，至少手工过一遍：

- [ ] 外屏在上、下、左、右四种排列，含负坐标
- [ ] 从主屏起拖跨到副屏，再从副屏起拖回主屏
- [ ] 区域模式下单击外屏窗口，截图尺寸和外屏窗口一致
- [ ] 窗口模式下分别点击内屏、外屏窗口
- [ ] 混合 1x/2x：工具栏显示的 px 尺寸等于该屏原生像素
- [ ] 跨屏选区的输出：方向正确、没有拉伸、屏幕空隙为黑
- [ ] 选区 origin 跨屏后，工具栏跟着回到正确的屏幕
- [ ] 固定某块屏的区域模式仍然只覆盖那一块屏
- [ ] 跨屏拖动后 `Enter` 确认、`Esc` 取消都有效
- [ ] 旋转屏/镜像屏至少确认不会崩溃（目前未专项适配）

## 7. 已知限制

- 覆盖层显示期间热插拔显示器、改分辨率不在处理范围内；窗口和 `referenceCg` 在 `show` 之前固定。
- 旋转屏、镜像屏没有做专项像素验证。
- 跨屏拖动依赖 AppKit 把拖拽事件持续投递给起始窗口；真机已验证，但以后如果引入事件监听层，要重新回归。
- 每次选区变化会重绘各屏的整张冻结图，没有做脏矩形优化；当前手感可接受，若以后加标注/放大镜再看。
- 工具栏跟随选区原点所在屏；把左上角把手拖过屏幕边界时，工具栏会跳到另一块屏。这是预期行为。
- 窗口截图不含阴影，这是 ScreenCaptureKit 的限制，与坐标系无关。

## 8. 相关代码入口

- `src/bridge/overlay_controller.m`
  - `SlimOverlayController initWithMode:...`：按屏建窗口、`referenceCg`、`selectionBounds`
  - `overlayViewDidChangeSelection:`：全局选区广播与工具栏宿主选择
  - `didSelectRegion:`：local → 全局，交给合成
  - `show`：按屏打印 `overlay screen N`
- `src/bridge/overlay_view.m`
  - `windowAtPoint:`：local → 全局后与 CG 原生窗口 rect 命中
  - `drawRect:` / `mouseDown:` / `mouseDragged:`：冻结画面绘制与框选交互
- `src/bridge/overlay_windows.m`
  - `SlimBuildWindowInfos`：CGWindowList 原生 rect + SCWindow 交叉确认
  - `SlimOverlayWindow`：可成为 key window 的无边框覆盖窗口
- `src/bridge/overlay_internal.h`：覆盖层模块之间的私有接口
- `src/bridge/capture.m`
  - `screenUnderMouse`：CGEvent + `CGGetDisplaysWithPoint` 找屏
  - `presentRegionOverlayWithCaptures:` / `presentWindowOverlayForScreen:`：进入覆盖层
- `src/bridge/capture_composite.m`
  - `SlimCopyCompositeFromCaptures`：混合 DPI 裁剪、拼接、填黑
  - `SlimCopyCropFromCapture`：单屏像素裁剪
- `src/bridge/screen_geometry.m`
  - `SlimScreenGlobalCGRect`：AppKit → CG 翻转
  - `SlimScreenForDisplayID` / `SlimScreenForSCDisplay`：display ID 匹配
- `src/bridge/overlay.h`：`SlimScreenCapture` 的 CGImage 所有权（retain/release 不归 ARC 管）
