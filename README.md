<div align="center">
  <img src="docs/icon.png" width="96" alt="Clip 图标">
  <h1>Clip</h1>
  <p><b>macOS 剪贴板历史管理器</b><br>按一下快捷键，历史就在手边。</p>
</div>

<p align="center">
  <b>简体中文</b> ·
  <a href="README_en.md">English</a> ·
  <a href="README_ja.md">日本語</a> ·
  <a href="README_fr.md">Français</a>
</p>

<div align="center">
  <img src="docs/img/剪切板1.png" width="820" alt="Clip 面板展开预览">
</div>

---

## 它解决什么

你复制了一段代码，切去查文档；回头再要用，剪贴板已经被新内容覆盖了。

Clip 在后台安静地记下你复制过的一切。**⇧⌘V** 随时呼出，方向键选一条，**回车** 直接粘到光标处。

<p align="center">
  <img src="docs/img/剪切板2.png" width="480" alt="Clip 紧凑面板">
</p>

没有窗口常驻，没有标签页，不用先想「我要找什么」——历史就摊在你面前，翻一下就行。

## 核心能力

### 什么都记得

文本、链接、颜色值、代码、文件路径、图片，复制什么记什么，每条都标着来自哪个应用。

<p align="center">
  <img src="docs/img/剪切板1.png" width="820" alt="分类识别与预览">
</p>

顶部一排药丸是分类筛选，带实时计数。截图、设计稿、复制的色值，各自归位不打架。

### 呼出即用

- **贴着光标弹出**，鼠标在哪就在哪出现；屏幕放不下时自动翻到另一侧
- **高度固定**，条目再多也只在列表内部滚动 —— 呼出的瞬间窗口不会上下跳
- **回车即粘**，直接送到当前光标处，不用手动切回上一个应用

### 看得清再决定

选中一条按 **→** 向右展开预览，**左上角固定不动**，正在看的列表不会横向跳动。图片点一下放大到屏幕尺寸比对，任意处或 `esc` 收起。

### 用键盘，也只用键盘

| 按键 | 作用 |
| --- | --- |
| <kbd>⇧⌘V</kbd> | 呼出 / 收起（可改成任意组合键） |
| <kbd>↑</kbd> <kbd>↓</kbd> | 选择 |
| <kbd>↵</kbd> | 粘贴到光标处 |
| <kbd>⌥↵</kbd> | 以纯文本粘贴（不带格式） |
| <kbd>→</kbd> <kbd>←</kbd> | 展开 / 收起预览 |
| <kbd>⌘1</kbd>–<kbd>⌘9</kbd> | 直接粘贴第 N 条 |
| <kbd>⌘P</kbd> | 置顶 / 取消置顶 |
| <kbd>⌘⌫</kbd> | 删除这一条 |
| <kbd>esc</kbd> | 收起面板 |

### 菜单栏里也能点

不方便用快捷键时，点状态栏图标也行。开关记录、看最近几条、直接从菜单栏粘贴。

<p align="center">
  <img src="docs/img/任务栏弹窗.png" width="520" alt="菜单栏面板">
</p>

### 桌面上也放一块

通知中心 / 桌面小组件显示最近几条历史，点一下即复制，点空白处呼出完整面板。

### 找到你要的那一条

顶部搜索框实时过滤。固定（⌘P）过的条目永远不会被自动清理，参数、地址、常备片段这类东西可以一直留在手边。

## 安装

需要 **macOS 27（Golden Gate）或更高版本**。

从 [Releases](https://github.com/wrm244/clip/releases) 下载 `.dmg`，拖进「应用程序」即可。

首次启动后菜单栏出现剪贴板图标。想让 Clip 帮你按下 <kbd>⌘V</kbd>，去 **系统设置 → 隐私与安全性 → 辅助功能** 勾选 Clip；不授权也能用，只是变成「复制好等你手动粘」并给个提示。

## 隐私

剪贴板能看见你复制的一切，所以这件事得说清楚：

- **默认忽略机密内容**。密码管理器（1Password、TypeIt4me 等）标记为机密的剪贴板内容不会被记录
- **不记录自己回填的内容**，也不会把你的历史再抄一遍
- **可以随时暂停记录**，一键开关
- **数据只在你本机**。历史存在 `~/Library/Application Support/Clip`，不上传、不同步、没有账号
- **可设上限**。条数（默认 300）和保留时长都可调，还能一键清空全部数据

## 许可

基于 [MIT](LICENSE) 协议发布，可以自由使用、修改与分发。

## 全部设置

**通用** —— 语言、记录开关、忽略机密内容、保留条数与时长、是否自动粘贴。

<p align="center">
  <img src="docs/img/设置通用.png" width="620" alt="设置 · 通用">
</p>

**外观** —— 深浅色、列表密度、是否显示来源应用、面板尺寸，以及「贴着光标弹出」还是「屏幕上方居中」。

<p align="center">
  <img src="docs/img/设置外观.png" width="620" alt="设置 · 外观">
</p>

**快捷键** —— 改全局呼出键，速查面板内的所有快捷键。

所有改动**立即生效**，没有「应用」按钮，不需要重启。

## 支持

- 中 / English 界面，设置里切换，随系统语言自动
- 深浅色外观，跟随系统或手动指定
- 登录时自动启动
- 支持「降低透明度」「增强对比度」「减弱动态效果」等系统辅助功能

---

<details>
<summary><b>开发者信息（构建 · 架构 · 实现细节）</b></summary>

### 技术栈

原生 SwiftUI + AppKit，**零第三方依赖**。菜单栏代理（`LSUIElement`）常驻，不占 Dock。SwiftData 增量持久化，图片等二进制外置为文件。

- 目标系统：macOS 27.0+，Swift 6（严格并发）
- 界面遵循 [Apple 人机界面指南](https://developer.apple.com/design/human-interface-guidelines/)，采用系统原生 Liquid Glass
- 签名：自签名证书 `Clip Self Signed`，保证辅助功能授权跨版本保留（原因见下）

### 构建

需要 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```bash
xcodegen generate                       # 由 project.yml 生成 Clip.xcodeproj
open Clip.xcodeproj                     # 在 Xcode 里 Run
```

命令行构建：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Clip.xcodeproj -scheme Clip \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build build
```

产物：`build/Build/Products/Release/Clip.app`

> 新增／删除源文件后需重新执行 `xcodegen generate`（工程按目录自动收集源文件）。
> 磁盘上不要同时存在多份 Clip.app（Debug / Release 各一份）——它们共用同一数据目录，
> 应用启动时会检测到另一份副本并主动让位。

### 打包与发版

```bash
Scripts/make-dmg.sh build/Build/Products/Release/Clip.app dist v1.0.8
```

`.github/workflows/release.yml` 在推 `v*` 标签后自动完成构建、打包、上传。
CI 签名需要两个 Secret：`P12_BASE64`（p12 的单行 base64）与 `P12_PASSWORD`。

### 代码签名为什么不用 ad-hoc

ad-hoc 签名没有稳定身份，macOS 给隐私授权（TCC，比如辅助功能）记录的指定要求只能是 `cdhash H"…"`——对整份二进制的哈希。每次重新构建 cdhash 都变，授权随即失效，用户更新后要重新授权。

换成自签名证书后，指定要求变成 `identifier "com.river.Clip" and certificate leaf = H"…"`，只与 bundle id + 证书绑定，二进制怎么变都保留授权。

证书一次性创建：「钥匙串访问 → 证书助理 → 创建证书…」，名称填 `Clip Self Signed`，身份类型「自签名根」，证书类型「代码签名」，然后设为「始终信任」。

> **p12 里必须同时有证书和私钥**。只导私钥会导入成功但组不出 identity。
> 用 `security export -t identities` 导出整条身份可以避免这个问题。

### 架构要点

**采集链路**：`NSPasteboard.general.changeCount` 每 0.4s 轮询一次（`Timer` + `tolerance` 0.2，对 CPU 几乎无影响）→ 变化时解析成 `ClipDraft` → 去重 / 转码 / 入库 → 增量写入 SwiftData。面板打开时前台应用是 Clip 自己，这种情况会延后重试而不是丢弃，避免漏采。

**并发模型**：`SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` + `SWIFT_STRICT_CONCURRENCY=complete`。UI 与状态在主 actor；数据库 / 文件 I/O、图片转码分别关在 `ClipStorage`、`ImageTranscoder` 两个 actor 里，主线程不碰 I/O。

SwiftData 的关键决策：`@Model` 类显式 `nonisolated`；`ModelContext` 在 actor 方法内懒创建（避免首访落在主队列）；`@Model` 实例不跨 actor 传递，对外只暴露 Sendable 的 `ClipItem` DTO；关闭 autosave、每次写操作显式 `save()`（强杀时 autosave 不可靠）；schema 用 `VersionedSchema` + `SchemaMigrationPlan` 起步。

**窗口**：`NSPanel(.borderless, .fullSizeContentView, .nonactivatingPanel)`，`canBecomeKey = true` 以便输入搜索，`level = .floating`。展开预览时只把窗口向右加宽、左上角固定，不重新计算位置。

**热键**：Carbon `RegisterEventHotKey`，C 回调里用 `MainActor.assumeIsolated` 回到主 actor。相比 `CGEventTap` 不需要辅助功能权限。

**防回环**：写回剪贴板时带 `com.river.clip.marker` 类型标记，轮询时看到它就跳过。

**菜单栏面板**：用 macOS 27 的 `NSStatusItem`「展开界面」会话（`NSStatusItemExpandedInterfaceDelegate`）而非 `NSPopover`——系统会话自带键盘导航与菜单跟踪行为。三条硬性约束：不能设 `menu`、不能用 target/action 手动 toggle、主动收起必须 `expandedInterfaceSession?.cancel()`。

**数据位置**：

```
~/Library/Application Support/Clip/
├── Clip.store      SwiftData 条目数据库（底层 SQLite）
├── Blobs/          PNG 原图、JPG 缩略图、RTF 富文本
└── Widget/         桌面小组件读的只读快照（feed.json + Thumbs/）
```

设置存于 `~/Library/Preferences/com.river.Clip.plist`。

### 目录结构

```
project.yml                 XcodeGen 工程定义
Support/Info.plist          LSUIElement、clip:// URL Scheme
Sources/
  App/                      入口、生命周期、应用级协调
  Models/                   条目模型、设置、快捷键
  Services/                 采集、解析、转码、存储、热键、粘贴
  UI/                       面板、预览、菜单栏面板、设置窗口
  Support/                  本地化、日志、Widget 快照
Widget/                     桌面小组件（只读快照方案）
Scripts/                    make-dmg.sh、seed-clipboard.swift
```

`Scripts/seed-clipboard.swift` 是开发辅助工具：按一份 JSON 清单依次写入系统剪贴板，用来快速生成各类型的测试数据。

```bash
swiftc -O Scripts/seed-clipboard.swift -o /tmp/clipseed
/tmp/clipseed run Scripts/seed-content.sample.json 1100
```

### 已知限制

- 「登录时启动」用 `SMAppService.mainApp`，应用不在 `/Applications` 下时可能失败，设置界面会显示错误
- 图片默认上限 8MB（超限自动降采样），条目默认上限 300 条，置顶条目永不淘汰
- 桌面小组件通过 `temporary-exception.files.home-relative-path.read-only` 读主 App 的快照目录 —— 这是无 App Group 构建下唯一可行的共享通道。若要上架 Mac App Store，应改用 App Group + 正式签名
- 小组件快照包含最近 12 条历史的标题文字（目前无法关闭）
- 用自签名证书签名；上架或公证分发需换成 Developer ID 证书

</details>

<p align="center">
  <sub>纯 SwiftUI + AppKit · 零第三方依赖 · 数据只在本机</sub>
</p>