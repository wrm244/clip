# Clip

原生、轻量、快速呼出的 macOS 剪贴板历史管理器。纯 SwiftUI + AppKit，**零第三方依赖**，以菜单栏代理（`LSUIElement`）方式常驻，不占 Dock。

- 目标系统：**macOS 27.0（Golden Gate）及以上**，Xcode 27，Swift 6（严格并发）
- 界面：SwiftUI + Liquid Glass（`glassEffect` / `NSGlassEffectView`）
- 数据：SwiftData（底层 SQLite）增量持久化，图片等二进制外置为文件，全部存放在 `~/Library/Application Support/Clip`

## 功能

| 能力 | 说明 |
| --- | --- |
| 全局快捷键 | 默认 ⇧⌘V 呼出，可在设置里改键；Carbon `RegisterEventHotKey`，**不需要任何权限** |
| 贴着光标弹出 | 面板出现在鼠标旁（右下优先，空间不足自动翻到左／上方并夹在屏幕内）；可在设置里改回屏幕上方居中 |
| 紧凑弹窗 | 高度固定为你设定的值，条目超出时列表内滚动；默认不显示预览，就是一个类似 Maccy 的小弹窗 |
| 预览按需展开 | **→**（或 ⌘Y）向右展开预览面板，**左上角固定不动**，列表不会跳；**←**（或 ⌘Y）收起 |
| 内容识别 | 文本 / 链接 / 颜色 / 图片 / 文件，自动分类并记录来源应用 |
| 搜索与筛选 | 顶部搜索框实时过滤；分类药丸带计数，窄弹窗下自动只留图标 |
| 键盘操作 | ↑↓ 选择、↵ 粘贴、⌥↵ 纯文本、→← 展开/收起预览、⌘P 固定、⌘⌫ 删除、⌘1–9 直接粘贴第 N 条 |
| 图片处理 | ImageIO 转码 + 生成缩略图，超限图片自动降采样，原图与缩略图分文件存放 |
| 去重 | SHA-256 内容指纹，重复内容只更新时间与使用次数 |
| 隐私 | 默认忽略密码管理器等标记为「机密」的剪贴板内容；也不会记录自己回填的内容 |
| 菜单栏面板 | `NSStatusItem` + `NSPopover`（真正的系统 popover，自动采用 Liquid Glass）；面板尺寸固定、底部动作永不被挤出 |
| 独立设置窗口 | 标准独立 `NSWindow`，**固定 720×640**，侧边栏分栏（通用／外观／快捷键／关于）；菜单栏、面板齿轮、⌘,、`clip://settings` 都能打开，还支持 `clip://settings/appearance` 直接定位到某一栏 |
| 其它 | 登录时启动、暂停记录、固定置顶、保留天数／条数上限、深浅色、全局快捷键自定义 |

## 界面设计

排版遵循 [Apple 人机界面指南](https://developer.apple.com/design/human-interface-guidelines/)：

- **玻璃用在功能层**：整个面板是一块玻璃（`NSGlassEffectView`），分类药丸和临时提示条是玻璃胶囊，
  搜索框用普通填充色，避免整个头部都是玻璃、层次不清。
  注意 `GlassEffectContainer` 会把距离**小于 spacing** 的玻璃形状融合成一团，
  所以药丸间距（8pt）必须明显大于融合距离（`glassBlendSpacing` = 3pt），否则它们就会「粘在一起」。
- **统一间距**：所有内边距、控件高度、间隔都由 `PanelMetrics` 集中定义（10 / 8 / 6pt 的 8pt 网格取值），
  分类之间固定 6pt，HIG 要求 “Use consistent spacing”。
- **形状用 macOS 27 的原生圆角 API**：窗口内容是一层 `PanelContainerView`，
  用 `NSView.cornerConfiguration`（`.uniformCorners(radius: .fixed(22))\`）声明形状，
  系统解析出 `effectiveCornerRadii` 后回调 `viewDidChangeEffectiveCornerRadii()`，
  再据此设置 layer 的 `mask`。
  为什么非要这一层：`NSGlassEffectView` 铺满整个窗口时会给自己画一圈柔和阴影，
  而窗口是矩形——那圈阴影只能落在**四角（圆角之外的空白处）**，
  屏幕上就是「圆角外面多出来一个方形边框」。容器按原生圆角把四角一裁就干净了，
  同时窗口 alpha 变成规整的圆角矩形，AppKit 的窗口阴影也能正确跟随这个形状。
  注意用 `layer.mask` 而不是 `masksToBounds`，后者会把 layer 自己的阴影一起裁掉。
- **紧凑**：搜索框 32pt、分类 24pt、行高 40（紧凑）/ 52（宽松）、状态栏 34pt；
  面板高度 = 头部 + 列表 + 状态栏；高度固定为设定值，条目多少都只影响列表内部滚动（避免呼出时窗口上下跳）。
- 窗口尺寸和 SwiftUI 布局共用 `PanelMetrics`，两边不会算出不同的高度。

## 构建

需要 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```bash
cd Clip
xcodegen generate                       # 由 project.yml 生成 Clip.xcodeproj
open Clip.xcodeproj                     # 然后在 Xcode 里 Run
```

命令行构建：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Clip.xcodeproj -scheme Clip \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build build
```

产物在 `build/Build/Products/Release/Clip.app`。

> 新增／删除源文件后要重新执行 `xcodegen generate`，工程是按目录自动收集源文件的。
> 磁盘上不要同时存在多份 Clip.app（例如 Debug 和 Release 各一份）——它们共用同一个数据目录；
> 应用启动时会检测到「另一份副本」并让位，避免两个进程互相覆盖历史。

## 使用

1. 启动 Clip，菜单栏出现剪贴板图标（没有 Dock 图标）。
2. 按 **⇧⌘V** 在鼠标旁呼出面板。
3. ↑↓ 选中，**↵** 粘贴到原来的应用；**esc** 关闭；**→** 展开预览、**←** 收起。
4. 想让 Clip 自动按下 ⌘V，需要在「系统设置 → 隐私与安全性 → 辅助功能」里勾选 Clip；
   未授权时会退化为「只复制 + 提示」，不会静默失败。

URL Scheme：`clip://show`、`clip://toggle`、`clip://menu`（打开菜单栏面板）、`clip://preview`（切换预览面板）、`clip://settings`。

## 快捷键一览

| 按键 | 作用 |
| --- | --- |
| ⇧⌘V（可改） | 呼出 / 收起面板 |
| ↑ / ↓ | 上下选择 |
| ↵ | 粘贴并关闭面板 |
| ⌥↵ | 以纯文本粘贴 |
| ⌘1–9 | 直接粘贴第 N 条 |
| ⌘P | 固定 / 取消固定 |
| ⌘⌫ | 删除选中条目 |
| → | 展开预览（搜索框为空时） |
| ← | 收起预览（搜索框为空时） |
| ⌘Y | 展开 / 收起预览 |
| ⌘, | 打开设置 |
| ⌘1 … ⌘9 | 直接粘贴第 N 条 |
| esc | 收起面板 |

## 暗色外观、动效与无障碍

这一版专门按 HIG 修了三类问题：

**1) 展开预览时的"列表回弹"**

原因是两件事叠在一起：预览面板用了 `→` 方向的位移过渡（`.move(edge: .trailing)`），
而动画又挂在**根视图**上（`.animation(..., value: store.previewVisible)`）——
挂在根上会把列表的滚动位置一起动画化，于是看起来就是列表在回弹。

改法（都对应 HIG 的明确条文）：

| 问题 | 改法 | 依据 |
| --- | --- | --- |
| 横向滑入 | 改成淡入淡出（`.opacity`） | HIG：用淡入替代 x/y/z 轴上的位移动画 |
| 带回弹的弹簧 | `.snappy` → `.smooth`（无回弹） | HIG：收紧弹簧、减少回弹 |
| 动画挂在根视图 | 动画只加在提示条自己身上，开合走 `setPreview(_:)` | HIG：高频交互不要加多余动效 |
| 减弱动态效果 | 打开时不做动画，直接切换 | HIG：动效要可关闭 |

**2) 暗色外观**

| 位置 | 问题（实测） | 改法 |
| --- | --- | --- |
| 菜单栏面板 | `NSPopover` 不跟随 `NSApp.appearance`：App 设成深色时整块面板仍是浅色（实测背景 235 + 深色文字） | 显示前显式同步一次 `popover.appearance`（这是 `NSPopover` 的已知行为，不是样式选择） |
| 呼出面板 | 玻璃通透程度**由系统决定** | 不设 `tintColor`，交给系统「外观 → 液态玻璃（通透/色调）」统一控制 |
| 面板文字 | 与系统对比度设置保持一致 | 统一用系统语义色 `.primary/.secondary/.tertiary`，不写死透明度 |
| 提示条阴影 | 黑色阴影在深色下看不见 | 深色下加深到 0.5 |

> **关于玻璃的通透程度**：macOS 27 把它做成了系统设置（全局偏好里的 `NSGlassTintAmount`，
> 对应「系统设置 → 外观 → 液态玻璃」的通透/色调）。`NSGlassEffectView` 会自动跟随这个设置，
> **App 不应该自己压明度**：`tintColor` 的用途是"把玻璃往某个色相上染"（例如品牌色），
> 拿它去调透明度等于覆盖用户自己的选择。
> 代价是深色外观下玻璃压在白窗口上会偏亮（实测表面 139、白字约 3.4:1）——
> 想要更实的底色，就把系统那档"色调"调高，而不是让 App 各自为政。

**3) 无障碍**

- **降低透明度**：`clipGlass` 内部自动换成不透明底色，呼出面板也铺一层不透明兜底（HIG：请为「降低透明度」提供实心背景）。
- **增强对比度**：分隔线用 `ClipSeparator`，打开后自动加深（HIG：增强对比度下要有更高对比度的方案）。
- **减弱动态效果**：开合预览、列表滚动都直接跳变，不做动画。

## 菜单栏面板为什么用 NSPopover

一开始用的是 SwiftUI 的 `MenuBarExtra(.window)`，它给的是一个**普通窗口**而不是真正的 popover：
一失焦就被收走，里面的按钮和菜单点不动（设置 / 清空 / 退出都点不动就是这么来的）。

现在改成 AppKit 的原生组合：

```swift
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
item.button?.action = #selector(toggleMenuBarPanel(_:))

let popover = NSPopover()
popover.behavior = .transient          // 点外面自动关，系统行为
popover.contentViewController = NSHostingController(rootView: MenuBarView()...)
popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
```

- `NSPopover` 是系统组件，**自动使用 Liquid Glass**（HIG 里 popover 正是用 `.regular` 玻璃的典型场景）。
- 行为可靠：`.transient` 点外面关，`performClose` 主动关，面板里的动作先 `MenuBarPanel.dismiss?()` 再执行。
- 打开面板前先 `rememberFrontmostApp()`，这样从菜单栏直接点某条记录粘贴时，⌘V 会发给正确的 App。
- 面板尺寸固定（340×336），底部用 `Spacer` 顶住，条目多少都不会把三个动作挤出窗口。

## 设置窗口

遵循 macOS 设置窗口的惯例：**侧边栏 + 分组表单**（`NavigationSplitView` + `Form(.grouped)`）。

### 液态玻璃怎么用（按 HIG，不是到处糊）

HIG 的原话是「Liquid Glass 是**导航和控件**的功能层」和「**不要在内容层使用 Liquid Glass**」，
所以玻璃都放在该放的地方，内容层保持朴素：

| 位置 | 做法 |
|---|---|
| 侧边栏 | 系统自带的玻璃层；窗口用 `titlebarAppearsTransparent` + `fullSizeContentView`，玻璃一直铺到窗口顶边，红绿灯浮在玻璃上 |
| 标题栏 | 透明、unified，内容滚动时自动获得 scroll edge effect；标题显示当前分栏名 |
| 最关键的动作 | 辅助功能未授权时的「去授权…」用 `.buttonStyle(.glass)` |
| 关于页 | App 标识是一张 `.glassEffect(.regular, in: .rect(cornerRadius: 16))` 玻璃卡片 |
| 弹出面板 | 整块 `NSGlassEffectView`（`.regular`，`effectIsInteractive`） |

其余部分刻意保持标准外观：HIG 明确说内容层不要用玻璃、
自定义控件上也要克制（"Limit these effects to the most important functional elements"）。

### 其它 HIG 细节

- 分栏：通用（采集／历史／粘贴／系统）、外观（主题／列表／面板）、快捷键（全局改键 + 面板内快捷键速查）、关于（版本／存储／清空）。
- **窗口尺寸固定 720×640**：切换分栏只换标题，窗口大小和位置都不动（内容多出来由表单自己滚动）。最小化与最大化按钮按 HIG 变灰。
- 改动立即生效，没有「应用」按钮；说明文字放在 `Section` 的 footer 里，而不是塞进行中间。
- 需要辅助功能权限时，行内直接显示状态并提供「去授权…」按钮，授权后无需重启。
- 「清空全部数据」是要确认的破坏性操作，弹 `confirmationDialog` 二次确认。
- 录制全局快捷键时会**先注销**当前全局热键，否则按到现有组合键会被直接吞掉、录不进来；取消或完成后自动恢复注册。
- 窗口位置会被记住（`setFrameUsingName` + `setFrameAutosaveName`），尺寸由当前分栏决定。
- `clip://settings/<general|appearance|shortcut|about>` 可以直接定位到某一栏，方便用其它工具做深链。

## 目录结构

```
project.yml                 XcodeGen 工程定义（macOS 27.0、Swift 6 严格并发、ad-hoc 签名）
Support/Info.plist          由 project.yml 生成（LSUIElement、clip:// URL Scheme）
Sources/
  App/
    ClipApp.swift           @main，AppKit 入口（NSApplication + AppDelegate）
    AppDelegate.swift       生命周期、主菜单、URL Scheme、单副本保护
    AppCoordinator.swift    应用级协调者：采集 → 存储 → 面板 → 粘贴
  Models/
    ClipItem.swift          条目模型（展示、搜索、时间格式化）
    ClipRecord.swift        SwiftData @Model（显式 nonisolated），与 ClipItem 双向映射
    ClipSettings.swift      @Observable 设置，逐项落 UserDefaults
    Shortcut.swift          快捷键模型（Carbon 修饰键 / 键码 / 显示名）
  Services/
    ClipboardMonitor.swift  changeCount 轮询采集（0.4s，带容差）
    PasteboardReader.swift  剪贴板解析：文件 → 文本/链接/颜色 → 图片
    PasteboardWriter.swift  写回剪贴板（带 `com.river.clip.marker` 防回环标记）
    ImageTranscoder.swift   actor，ImageIO 转码 + 缩略图 + 尺寸限制
    ContentHash.swift       SHA-256 内容指纹（CryptoKit）
    ClipStorage.swift       actor，SwiftData 记录 CRUD（每笔写显式 save）+ Blobs/ 文件读写与清理
    ClipStore.swift         @Observable 列表状态：去重、排序、筛选、淘汰、串行化增量落库
    HotKeyCenter.swift      Carbon 全局热键
    PasteService.swift      辅助功能授权检查 + CGEvent ⌘V 回填
    ImageCache.swift        NSCache 缩略图 / 预览图缓存
    LaunchAtLogin.swift     SMAppService 登录项
  UI/
    PanelMetrics.swift      面板排版的唯一来源：间距、圆角、行高、窗口尺寸
    PanelController.swift   无边框 NSPanel、光标定位、按需缩放、按键映射
    ClipPanelView.swift     面板根视图：搜索 + 分类 + 列表 + 预览 + 状态栏
    ClipRowView.swift       单行条目
    PreviewPane.swift       右侧预览（320pt）
    MenuBarView.swift       菜单栏下拉面板（装进 NSPopover）
    SettingsView.swift      设置内容：侧边栏 + 分组表单（通用 / 外观 / 快捷键 / 关于）
    SettingsWindow.swift    设置窗口本身：标准 NSWindow，负责开窗、尺寸与位置记忆
    PanelContainerView.swift 面板窗口形状：macOS 27 原生圆角 API + 裁剪
    Components.swift        分类药丸、键帽、提示条、空状态
  Support/
    Log.swift               统一 os.Logger
    AppKitExtras.swift      颜色工具
  Resources/Assets.xcassets AppIcon
```

## 架构要点

**采集链路**：`NSPasteboard.general.changeCount` 每 0.4s 轮询一次（`Timer` + `tolerance` 0.2，对 CPU 几乎无影响）→ 变化时解析成 `ClipDraft` → `ClipStore.ingest` 去重 / 转码 / 入库 → 增量写入 SwiftData（每笔改动立即落库，只写受影响的行，没有全量重写）。
面板打开时前台应用就是 Clip 自己，这种情况会**延后重试**而不是直接丢弃，避免漏采。

**并发模型**：`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` + `SWIFT_STRICT_CONCURRENCY=complete`。
UI 与状态都在主 actor；数据库与文件 I/O、图片转码分别关在 `ClipStorage`、`ImageTranscoder` 两个 actor 里，主线程不碰 I/O。
SwiftData 相关的几个关键决策：

- `@Model` 类显式 `nonisolated`（否则会被默认隔离隐式推断成主线程隔离，无法在后台 actor 的 context 里使用）；
- `ClipStorage` 是普通 actor，在 actor 方法内**懒创建** `ModelContext`（落在私有串行队列，不会因首访在主线程而退化成主队列），不用 `@ModelActor`（它的 context 队列绑定创建线程）；
- `@Model` 实例不是 Sendable，绝不跨 actor 传递，对外只暴露 `ClipItem`（Sendable DTO）；
- 关闭 autosave、每次写操作显式 `save()`（强杀时 autosave 不可靠）；
- `ClipStore` 的所有落库操作经一个串行任务链排队，写入顺序与内存改动顺序严格一致；
- schema 用 `VersionedSchema`（v1）+ `SchemaMigrationPlan` 起步，未来模型演进走显式、可控的迁移路径；
- 刻意**不用** macOS 27 的 `ResultsObserver` / `@Query`：`ClipStore` 是唯一写入者，内存数组就是事实来源，引入跨 context 观测没有收益。

**窗口**：`NSPanel(.borderless, .fullSizeContentView, .nonactivatingPanel)`，`canBecomeKey = true` 以便输入搜索，
`level = .floating`，`collectionBehavior` 允许跟随所有空间。内容套一层 `NSGlassEffectView`
（`cornerRadius` 取自 `PanelMetrics`、`effectIsInteractive = true`，后者是 macOS 27 才有的交互反馈）。

**定位与缩放**：呼出时按鼠标位置计算原点（右下优先 → 翻转到左上 → 夹进屏幕可视区域）；
展开预览时**不重新计算位置**，只把窗口向右加宽并保持左上角固定，所以列表不会跳动。

**热键**：Carbon `RegisterEventHotKey`，C 回调里用 `MainActor.assumeIsolated` 回到主 actor；
相比 `CGEventTap` 不需要辅助功能权限。

**防回环**：写回剪贴板时带一个 `com.river.clip.marker` 类型，轮询时看到它就跳过。

**数据安全**：条目存进 SwiftData（`Clip.store`，底层 SQLite），每次写操作显式 `save()`，
强杀进程也不丢数据；数据库打开失败时回退到内存容器并打日志，绝不用空库覆盖原文件；
启动时还会让位给已经存在的另一份副本。

## 数据位置

```
~/Library/Application Support/Clip/
├── Clip.store      SwiftData 条目数据库（底层 SQLite，随写随存；另生成 -wal / -shm）
└── Blobs/          PNG 原图、JPG 缩略图与 RTF 富文本
```

设置存在 `~/Library/Preferences/com.river.Clip.plist`。设置里的「在访达中显示」可以直接跳过去。

## 说明与限制

- 自动粘贴依赖辅助功能权限；未授权时只复制到剪贴板并提示。
- 使用 ad-hoc 签名（`CODE_SIGN_IDENTITY = "-"`），每次重新构建后系统可能要求重新授权辅助功能。
  分发时请换成自己的开发者证书。
- 「登录时启动」用 `SMAppService.mainApp`，应用不在 `/Applications` 下时可能失败，设置界面会显示错误。
- 图片默认上限 8MB（超限会降采样），条目默认上限 300 条，固定条目永不淘汰。
