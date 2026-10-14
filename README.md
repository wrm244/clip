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
| 预览按需展开 | **→**（或 ⌘Y）向右展开预览面板，**左上角固定不动**、带 0.24s 宽度动画，列表不会跳；**←**（或 ⌘Y）收起 |
| 内容识别 | 文本 / 链接 / 颜色 / 图片 / 文件，自动分类并记录来源应用 |
| 搜索与筛选 | 顶部搜索框实时过滤；分类药丸带计数，窄弹窗下自动只留图标 |
| 键盘操作 | ↑↓ 选择、↵ 粘贴、⌥↵ 纯文本、→← 展开/收起预览、⌘P 固定、⌘⌫ 删除、⌘1–9 直接粘贴第 N 条 |
| 图片处理 | ImageIO 转码 + 生成缩略图，超限图片自动降采样，原图与缩略图分文件存放 |
| 图片放大查看 | 预览面板里**点击图片**弹出居中的大图浮层：等比适配到屏幕可视区（不放大超出原始像素），底部胶囊显示像素尺寸；**点击任意处或按 esc** 关闭，焦点自动还给面板 |
| 去重 | SHA-256 内容指纹，重复内容只更新时间与使用次数 |
| 隐私 | 默认忽略密码管理器等标记为「机密」的剪贴板内容；也不会记录自己回填的内容 |
| 菜单栏面板 | `NSStatusItem` + macOS 27 的「展开界面」会话（`NSStatusItemExpandedInterfaceDelegate`），面板本体 `NSGlassEffectView`；面板尺寸固定、底部动作永不被挤出 |
| 独立设置窗口 | 标准独立 `NSWindow`，**固定 720×640**，侧边栏分栏（通用／外观／快捷键／关于）；菜单栏、面板齿轮、⌘,、`clip://settings` 都能打开，还支持 `clip://settings/appearance` 直接定位到某一栏 |
| 多语言 | 中文（简体）/ English，设置里可切；**切换立即生效**，无需重启；「跟随系统」按 macOS 首选语言自动选择 |
| 桌面小组件 | 通知中心 / 桌面上显示最近几条历史；点某条即复制，点空白处呼出面板（主 App 导出只读快照，小组件无需额外权限） |
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

## 多语言（中 / 英）

界面语言在「设置 → 通用 → 语言」里切换，默认「跟随系统」：`zh*` 走简体中文，其余回退英文。
切换是**立即生效**的，和这套设置里其它开关一致，不需要重启。

实现上没有用 `.lproj` 或 String Catalog，而是一张纯 Swift 的文案表（`Sources/Support/Localization*.swift`）：

- **以中文源文本作为 key**（Apple 的 source-language-as-key 惯例）。中文本身是源语言，
  查不到就直接用 key，所以**不需要再维护一份中文表**；英文表里只列需要翻译的串。
- 需要插入变量的串用 printf 风格格式串作 key（`"%ld 项"`、`"版本 %@（%@）"`），
  用 `String(format:)` 填充，避免中英语序差异。
- 日期/时间用 Foundation 的 `RelativeDateTimeFormatter`（跟随当前语言自动处理单复数与语序，
  例如 `1m ago` / `1分钟前`）；字节数用 `ByteCountFormatter`。
- `Localization` 是 `@Observable` 的单例，`L("…")` 在 SwiftUI `body` 里会读到它，
  于是切换语言时所有用到文案的视图自动重建，**不用重建任何 hosting 视图**。
- AppKit 侧（主菜单、状态项 tooltip、设置窗口标题）以及按语言缓存的列表搜索索引 / 副标题，
  由 `ClipSettings.onLanguageChange` → `AppCoordinator.applyLanguage()` 显式刷新。

为什么这么选：这套界面几乎全部是代码里拼出来的（模型计算属性、AppKit 菜单、toast），
且设置改动要求立即生效。走 bundle 本地化要在运行期切换 SwiftUI 的 `Bundle`，
要么重建全部 hosting 视图，要么等系统重启，代价和不确定性都更高；一张 Swift 表则简单、可控、零依赖。

添加新文案：在代码里用 `L("中文源文本")`（或带参数 `L("%ld 项", n)`），
再到 `LocalizationEnglish.swift` 补一条英文即可；漏翻译会回退成中文，不会显示成 key。

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

### 代码签名（自签名证书）

工程用自签名证书 `Clip Self Signed` 签名（`project.yml` 里 `CODE_SIGN_IDENTITY`），**不要退回 ad-hoc**。

**为什么必须换掉 ad-hoc**：ad-hoc 签名没有稳定身份，macOS 给隐私授权（TCC，比如「辅助功能」）记录
的「指定要求」只能是 `cdhash H"…"`——对整份二进制的哈希。每次重新构建 / 发新版 cdhash 都变，
授权随即失效，用户更新后要重新授权。换成自签名证书后指定要求变成
`identifier "com.river.Clip" and certificate leaf = H"…"`，只与 bundle id + 证书绑定，**二进制怎么变都保留授权**。
（切换后需要「删掉旧的辅助功能条目 → 重新授权」一次，之后覆盖安装就不用再授权了。）

创建证书（一次性，不用花钱）：

1. 「钥匙串访问」→ 菜单「钥匙串访问 → 证书助理 → 创建证书…」；
2. 名称填 `Clip Self Signed`，身份类型选「自签名根」，证书类型选「代码签名」，其余默认；
3. 双击该证书 → 展开「信任」→「使用此证书时」设为「始终信任」；
4. 验证：`security find-identity -v -p codesigning` 应列出 `"Clip Self Signed"`。

证书本身就是 App 的身份，**别弄丢或重建**（重建 = 换身份，授权又会重置）。换机器时把证书导成 `.p12`
再 `security import` 回来即可。`.p12` 已被 `.gitignore` 忽略，不会入库。

#### CI 签名证书

`release.yml` 在构建前从 GitHub Secrets 导入证书：

- `P12_BASE64`：p12 的**单行** base64（见下）
- `P12_PASSWORD`：导出 p12 时设置的密码

两个 Secret 都没配时，CI 自动回退 ad-hoc 签名（仍能出包，但用户更新后要重新授权辅助功能）。

> ⚠️ **p12 里必须同时有「证书」和「私钥」**。只导出私钥的 p12 里没有证书，
> `security import` 会成功但组不出 identity，CI 会报「未找到代码签名身份」。
> 「钥匙串访问」里要选中 **「我的证书」** 分类下、左边带小三角（可展开出私钥）的
> `Clip Self Signed` **整条身份**再导出；只选「密钥」分类里的条目导出的就是无证书的私钥。

推荐用命令行导出整条身份（会连证书一起打包），并直接生成单行 base64：

```bash
# 1) 导出身份（提示输入的「导出密码」要和第 3 步一致）
security export -k "$HOME/Library/Keychains/login.keychain-db" -t identities \
  -f pkcs12 -P '你的导出密码' -o /tmp/Clip-Identity.p12

# 2) 自检：证书、私钥都应各打印 1
openssl pkcs12 -in /tmp/Clip-Identity.p12 -nokeys  -passin 'pass:你的导出密码' | grep -c 'BEGIN CERTIFICATE'
openssl pkcs12 -in /tmp/Clip-Identity.p12 -nocerts -nodes -passin 'pass:你的导出密码' | grep -c 'BEGIN.*PRIVATE KEY'

# 3) 生成单行 base64 → 剪贴板 → 粘贴进 P12_BASE64
base64 -i /tmp/Clip-Identity.p12 | tr -d '\n' | pbcopy
```

> `security export -t identities` 会把钥匙串里**所有**身份都导出；本机只有 `Clip Self Signed` 一条。
> 若有多条，改用「钥匙串访问」只导出指定那一条。仓库根目录那个 `Clip Self Signed.p12`
> 就是只含私钥的坏样本，别再拿它做 Secret（已在 `.gitignore` 忽略）。

### 打包 DMG

用仓库自带的脚本（只用系统工具，macOS 27 起走 `diskutil image create` 而非已废弃的 `hdiutil create`）：

```bash
Scripts/make-dmg.sh build/Build/Products/Release/Clip.app dist v1.0.6
# → dist/Clip-1.0.6.dmg（内含 /Applications 软链接，拖进去即可安装）
```

### 自动发版（GitHub Actions）

`.github/workflows/release.yml`：推一个 `v*` 标签（或在 Actions 页手动触发并填版本号）就会自动
`xcodegen generate` → Release 编译 → 打 DMG → 传上 GitHub Release。
版本号取自标签（`v1.2.0-beta.1` 会把 `CFBundleShortVersionString` 写成 `1.2.0`），
构建号用 run number，所以 DMG 里的版本跟标签一致。

```bash
git tag v1.0.6 && git push origin v1.0.6
```

可用仓库变量微调：`MACOS_RUNNER`（默认 `macos-27`）、`CLIP_XCODE_VERSION`、`CLIP_ARCHS`（默认 `arm64`，
macOS 27 已不支持 Intel）。初次推送标签前记得先配好 git remote。

## 使用

1. 启动 Clip，菜单栏出现剪贴板图标（没有 Dock 图标）。
2. 按 **⇧⌘V** 在鼠标旁呼出面板。
3. ↑↓ 选中，**↵** 粘贴到原来的应用；**esc** 关闭；**→** 展开预览、**←** 收起。
   预览里**点击图片**可以放大查看（点击任意处或按 **esc** 收起大图）。
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
| 点击预览里的图片 | 放大查看（点击任意处或 esc 关闭） |
| ⌘, | 打开设置 |
| ⌘1 … ⌘9 | 直接粘贴第 N 条 |
| esc | 收起面板 |

## 暗色外观、动效与无障碍

这一版专门按 HIG 修了三类问题：

**1) 展开预览的动效**

硬切和回弹都不对。最早预览面板用 `→` 方向的位移过渡（`.move(edge: .trailing)`），
动画又挂在**根视图**上（`.animation(..., value: store.previewVisible)`），
而窗口尺寸是瞬间变化的——窗口已经变宽、内容还在路上，看起来就是列表在回弹。
当时的处理是把动效整个去掉，于是又变成了「啪」地硬切。

现在只给**窗口**做动画，内容完全不自己跑动画：

- 窗口：`NSAnimationContext` + `panel.animator().setFrame(...)`，0.24s `.easeInEaseOut`；
- 内容：`ClipPanelView` 用 `GeometryReader` 拿窗口的**实时宽度**，反推出展开进度
  `PanelMetrics.previewProgress`；列表宽度、预览露出多少、分隔线宽度都由这一个进度
  算出来。动画的每一帧内容都正好等于窗口宽度，既不会溢出被裁，也不会在右边留白；
- 预览窗格：内容固定 `previewWidth` 宽、靠左对齐，进度只决定「露出多少」，
  再配一点淡入。文字不会跟着窗口重排，也没有横向位移。

| 问题 | 改法 | 依据 |
| --- | --- | --- |
| 窗口瞬间变宽 + 内容自己动画 → 错位回弹 | 只动画窗口；内容由窗口实时宽度反推进度，天然同帧 | — |
| 横向滑入 | 预览窗格按进度裁切 + 淡入，不做位移 | HIG：用淡入替代 x/y/z 轴上的位移动画 |
| 带回弹的弹簧 | 窗口动效用 `.easeInEaseOut`，无回弹 | HIG：收紧弹簧、减少回弹 |
| 高频交互 | 时长压到 0.24s，且只在开合预览时发生 | HIG：高频交互不要加多余动效 |
| 减弱动态效果 | 打开时直接切换（`accessibilityDisplayShouldReduceMotion`） | HIG：动效要可关闭 |

**2) 暗色外观**

| 位置 | 问题（实测） | 改法 |
| --- | --- | --- |
| 菜单栏面板 | 面板是不跟随 App 外观的独立窗口 | 每次显示前显式设置一次 `panel.appearance`（`NSPanel` 不会自动继承 `NSApp.appearance`） |
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
- **减弱动态效果**：开合预览、列表滚动都直接跳变，不做动画（开合预览读 `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`）。

## 菜单栏面板为什么用「展开界面」会话（不是 NSPopover）

最早用的是 SwiftUI 的 `MenuBarExtra(.window)`，它给的是一个**普通窗口**：
一失焦就被收走，里面的按钮和菜单点不动（设置 / 清空 / 退出都点不动就是这么来的）。

后来也用过 `NSStatusItem` + `NSPopover`（系统组件，行为可靠）。
到了 macOS 27，AppKit 给状态项提供了一套更贴合菜单栏语义的
**展开界面（expanded interface）会话**，因此整体迁移到它：

```swift
// 不设 menu、不设 button 的 target/action——否则系统不会走会话回调
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
item.expandedInterfaceDelegate = self
// 用户点击状态项 → 系统建立会话并回调：
//   func statusItem(_:didBegin:)                                  → 显示面板
//   func statusItemDidEndExpandedInterfaceSession(_:animated:)    → 收起面板
// 我们自己收起（点面板里的动作）时：
//   item.expandedInterfaceSession?.cancel()
```

- 面板显示 / 收起、键盘导航、Esc、点击状态项再次关闭，都交给系统会话（Apple 文档称
  “allows participation in keyboard navigation and menu tracking behaviors”）。
  `NSPopover` 这些行为要靠 `.transient` 自己拼，且和状态项是两套状态。
- 三条硬性约束（来自 `NSStatusItem.h` 与 Apple 文档）：**不能设 `menu`**、
  **不能再用 target/action 手动 toggle**、**主动收起必须 `cancel()` 会话**。
- 会话中点击本 App 的其它窗口不会自动结束会话，所以补了一个 local mouse-down 监视器
  （正是头文件里建议的 `NSEvent.addLocalMonitorForEventsMatchingMask:handler:`），
  它跳过状态项自身窗口和层级更高的菜单窗口，避免误关。
- 面板本体是 `NSGlassEffectView`（`.regular` + `effectIsInteractive`）装 `NSHostingView`，
  外面套 `PanelContainerView` 用 macOS 27 原生圆角 API 裁形——和快速呼出面板同一套观感。
- 显示前先 `rememberFrontmostApp()`，这样从菜单栏直接点某条记录粘贴时，⌘V 会发给正确的 App。
- 面板尺寸固定（340×336），底部用 `Spacer` 顶住，条目多少都不会把三个动作挤出窗口。
- 定位贴着状态项正下方、右对齐；状态项尚未完成布局导致锚点无效时回退到主屏右上角。

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
project.yml                 XcodeGen 工程定义（macOS 27.0、Swift 6 严格并发、自签名证书）
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
    WidgetFeedWriter.swift  主 App 侧：把最近历史导出成小组件只读快照（防抖写盘 + 刷新时间线）
    HotKeyCenter.swift      Carbon 全局热键
    PasteService.swift      辅助功能授权检查 + CGEvent ⌘V 回填
    ImageCache.swift        NSCache 缩略图 / 预览图缓存
    LaunchAtLogin.swift     SMAppService 登录项
  UI/
    PanelMetrics.swift      面板排版的唯一来源：间距、圆角、行高、窗口尺寸
    PanelController.swift   无边框 NSPanel、光标定位、按需缩放、按键映射
    ClipPanelView.swift     面板根视图：搜索 + 分类 + 列表 + 预览 + 状态栏
    ClipRowView.swift       单行条目
    PreviewPane.swift       右侧预览（320pt，点击图片可放大）
    ImageLightboxController.swift 图片放大浮层：居中大图 + 尺寸提示胶囊，点击任意处 / esc 关闭
    MenuBarView.swift       菜单栏下拉面板内容（装进展开界面会话的窗口）
    MenuBarPanelController.swift 状态项 + 展开界面会话（didBegin/didEnd/cancel）、面板窗口定位、点击别处收起
    SettingsView.swift      设置内容：侧边栏 + 分组表单（通用 / 外观 / 快捷键 / 关于）
    SettingsWindow.swift    设置窗口本身：标准 NSWindow，负责开窗、尺寸与位置记忆
    PanelContainerView.swift 面板窗口形状：macOS 27 原生圆角 API + 裁剪
    Components.swift        分类药丸、键帽、提示条、空状态
  Support/
    Log.swift               统一 os.Logger
    Localization.swift      运行时本地化：AppLanguage / Localization 单例 / L(_:)
    LocalizationEnglish.swift 英文文案表（key 为中文源文本）
    WidgetFeed.swift        主 App 与小组件共享的快照模型 + 磁盘路径（getpwuid 取真实 home）
    AppKitExtras.swift      颜色工具
  Resources/Assets.xcassets AppIcon

Widget/
  ClipWidget.swift          小组件本体：TimelineProvider + 各尺寸视图
  ClipWidgetBundle.swift    小组件扩展入口
  ClipWidget.entitlements   沙盒 + 只读临时例外（读主 App 的快照目录）
  Info.plist                由 project.yml 生成
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

**桌面小组件**：小组件是独立沙盒进程，打不开主 App 的 SwiftData 库；而本工程是免签构建，
App Group 会被系统忽略（trustd 报 `invalid application signature`）。所以走第三条路：主 App（未沙盒）
把最近 12 条预渲染成一份只读快照 `Widget/feed.json` + `Widget/Thumbs/`（标题、副标题都已按当前界面语言
渲染好，小组件不必带本地化表），写完调 `WidgetCenter.reloadAllTimelines()`；
小组件在 entitlements 里声明 `temporary-exception.files.home-relative-path.read-only` 只读该目录。
因为沙盒里 `NSHomeDirectory()` 会指向自己的容器，两边都用 `getpwuid(getuid()).pw_dir` 拼真实 home。
快照写入做了 700ms 防抖，历史变化频繁时合并成一次写盘。

**数据安全**：条目存进 SwiftData（`Clip.store`，底层 SQLite），每次写操作显式 `save()`，
强杀进程也不丢数据；数据库打开失败时回退到内存容器并打日志，绝不用空库覆盖原文件；
启动时还会让位给已经存在的另一份副本。

## 数据位置

```
~/Library/Application Support/Clip/
├── Clip.store      SwiftData 条目数据库（底层 SQLite，随写随存；另生成 -wal / -shm）
├── Blobs/          PNG 原图、JPG 缩略图与 RTF 富文本
└── Widget/         桌面上小组件读的只读快照（feed.json + Thumbs/），主 App 自动维护
```

设置存在 `~/Library/Preferences/com.river.Clip.plist`。设置里的「在访达中显示」可以直接跳过去。

## 说明与限制

- 自动粘贴依赖辅助功能权限；未授权时只复制到剪贴板并提示。
- 用自签名证书 `Clip Self Signed` 签名（见「构建 → 代码签名」）。这样辅助功能授权能跨版本保留；
  若为 ad-hoc 签名，每次重新构建 / 更新都会要求重新授权。想上架或公证分发则需换成 Developer ID 证书。
- 「登录时启动」用 `SMAppService.mainApp`，应用不在 `/Applications` 下时可能失败，设置界面会显示错误。
- 图片默认上限 8MB（超限会降采样），条目默认上限 300 条，固定条目永不淘汰。
- 桌面小组件靠 `temporary-exception.files.home-relative-path.read-only` 读主 App 的快照目录。
  这是没有 App Group 的构建下唯一可行的共享通道；App Group 需要 Team ID 与描述文件，自签名下同样会被忽略。
  若要上架 Mac App Store / 公证分发，应改用 App Group 并配上正式签名。
  快照里会包含最近 12 条历史的标题文字，请注意这一隐私面（目前无法关闭）。
