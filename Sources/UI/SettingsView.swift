import AppKit
import SwiftUI

/// 设置窗口的四个分栏。
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case appearance
    case shortcut
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .appearance: "外观"
        case .shortcut: "快捷键"
        case .about: "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .shortcut: "command"
        case .about: "info.circle"
        }
    }

    /// 分栏标题下的一句说明。
    var subtitle: String {
        switch self {
        case .general: "记录、保留、粘贴与系统集成"
        case .appearance: "主题、列表与面板"
        case .shortcut: "全局呼出快捷键与面板内操作"
        case .about: "版本、存储与数据"
        }
    }
}

/// 设置窗口。
///
/// 用侧边栏 + 分组表单，这是 macOS 上设置窗口的标准形态：
/// 分栏放左边便于切换，右侧用 Form(.grouped) 让每一行的控件自动右对齐，
/// 说明文字放在 Section 的 footer 里，而不是塞在行中间。
/// 设置窗口的当前分栏。放在模型里，窗口控制器就能指定打开哪一栏
/// （例如 clip://settings/appearance）。
@MainActor
@Observable
final class SettingsUIModel {
    var pane: SettingsPane = .general
}

struct SettingsView: View {
    /// 分栏切换时通知窗口控制器调整窗口大小和标题。
    var onPaneChange: ((SettingsPane) -> Void)?

    @Environment(SettingsUIModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $model.pane) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 185, max: 230)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            // 分栏标题放在滚动区域**外面**：内容再怎么滚也不会和标题重叠。
            // 这也是 macOS「系统设置」的做法——标题栏留空，标题写在各栏内容里。
            VStack(alignment: .leading, spacing: 0) {
                paneHeader
                paneBody
            }
        }
        .onChange(of: model.pane) { _, newValue in
            onPaneChange?(newValue)
        }
    }

    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.pane.title)
                .font(.system(size: 17, weight: .semibold))
            Text(model.pane.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var paneBody: some View {
        switch model.pane {
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .shortcut: ShortcutSettings()
        case .about: AboutSettings()
        }
    }
}

// MARK: - 通用

struct GeneralSettings: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(ClipSettings.self) private var settings
    @Environment(PasteService.self) private var paste

    @State private var launchError: String?
    @State private var usage = 0

    var body: some View {
        Form {
            Section {
                Toggle("记录剪贴板内容", isOn: Bindable(settings).isMonitoringEnabled)
                Toggle("忽略密码管理器等敏感内容", isOn: Bindable(settings).ignoreConcealed)
            } header: {
                Text("采集")
            } footer: {
                Text("暂停记录不会影响已经保存的历史。被标记为机密的剪贴板内容始终不会被记录。")
            }

            Section {
                Picker("最多保留", selection: Bindable(settings).maxItems) {
                    Text("100 条").tag(100)
                    Text("300 条").tag(300)
                    Text("500 条").tag(500)
                    Text("1000 条").tag(1000)
                }
                Picker("保留时长", selection: Bindable(settings).retentionDays) {
                    Text("永久").tag(0)
                    Text("1 天").tag(1)
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                }
                LabeledContent("当前占用") {
                    Text("\(coordinator.store.items.count) 条 · \(ClipItem.byteText(usage))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } header: {
                Text("历史")
            } footer: {
                Text("固定（置顶）的条目永远不会被自动清理；保留时长按条目最后一次使用的时间计算。")
            }

            Section {
                Toggle("选中后自动粘贴到前台应用", isOn: Bindable(settings).autoPaste)
                Toggle("复制时播放提示音", isOn: Bindable(settings).playSound)
                LabeledContent("辅助功能权限") { permissionStatus }
            } header: {
                Text("粘贴")
            } footer: {
                Text(paste.isTrusted
                     ? "已获得辅助功能权限，选中条目后 Clip 会自动按下 ⌘V。"
                     : "未授权时 Clip 只会把内容复制到剪贴板，不会自动粘贴。授权后无需重启即可生效。")
            }

            Section("系统") {
                Toggle("登录时启动 Clip", isOn: launchAtLogin)
                if let launchError {
                    Label(launchError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                LabeledContent("数据目录") {
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([ClipStorage.shared.rootURL])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            paste.refreshTrust()
            usage = await coordinator.store.diskUsage()
        }
    }

    @ViewBuilder
    private var permissionStatus: some View {
        HStack(spacing: 10) {
            Label(
                paste.isTrusted ? "已授权" : "未授权",
                systemImage: paste.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(paste.isTrusted ? Color.green : Color.orange)
            if !paste.isTrusted {
                // 整个设置里最重要的一个动作，按 HIG「只给最关键的功能元素用玻璃」
                Button("去授权…") { paste.requestAccess() }
                    .buttonStyle(.glass)
            }
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { LaunchAtLogin.isEnabled },
            set: { newValue in launchError = LaunchAtLogin.setEnabled(newValue) }
        )
    }
}

// MARK: - 外观

struct AppearanceSettings: View {
    @Environment(ClipSettings.self) private var settings

    var body: some View {
        Form {
            Section("主题") {
                Picker("外观", selection: Bindable(settings).appearance) {
                    ForEach(ClipSettings.Appearance.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                Picker("列表密度", selection: Bindable(settings).density) {
                    ForEach(ClipSettings.Density.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("显示来源应用", isOn: Bindable(settings).showSourceApp)
                Toggle("展开预览面板", isOn: Bindable(settings).showPreview)
            } header: {
                Text("列表")
            } footer: {
                Text("预览面板会在打开时默认展开，也可以随时用 → 或 ⌘Y 展开，← 收起。")
            }

            Section {
                Toggle("在鼠标位置弹出", isOn: Bindable(settings).popupAtMouse)
                LabeledContent("面板宽度") {
                    measurement(Bindable(settings).panelWidth, range: 360...900, unit: "pt")
                }
                LabeledContent("面板高度") {
                    measurement(Bindable(settings).panelHeight, range: 320...900, unit: "pt")
                }
            } header: {
                Text("面板")
            } footer: {
                Text("关闭「在鼠标位置弹出」后，面板固定在屏幕上方居中显示。面板高度是固定值，条目超出时在列表内滚动；展开预览时只向右加宽。")
            }
        }
        .formStyle(.grouped)
    }

    /// 滑杆 + 实时数值。数值用等宽数字，拖动时不会左右抖动。
    private func measurement(_ value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        HStack(spacing: 10) {
            Slider(value: value, in: range, step: 20)
            Text("\(Int(value.wrappedValue)) \(unit)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

// MARK: - 快捷键

struct ShortcutSettings: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(ClipSettings.self) private var settings

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("全局快捷键") {
                    HStack(spacing: 8) {
                        recorderButton
                        Button {
                            settings.hotkey = .panelDefault
                            message = "已恢复为默认快捷键"
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(settings.hotkey == .panelDefault)
                        .help("恢复默认快捷键")
                    }
                }
                if let message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("呼出面板")
            } footer: {
                Text(isRecording
                     ? "直接按下想要的组合键，需要包含 ⌘、⌥ 或 ⌃；按 esc 取消。录制期间全局快捷键会暂时停用。"
                     : "在其他应用里按下这个组合键即可呼出面板。点击按键可以重新录制。")
            }

            Section("面板内快捷键") {
                shortcutRow("↑  ↓", "上下选择")
                shortcutRow("↩", "粘贴选中项")
                shortcutRow("⌥ ↩", "以纯文本粘贴")
                shortcutRow("⌘ 1 … ⌘ 9", "直接粘贴第 N 条")
                shortcutRow("⌘ P", "固定 / 取消固定")
                shortcutRow("⌘ ⌫", "删除选中项")
                shortcutRow("→  ←", "展开 / 收起预览")
                shortcutRow("esc", "关闭面板")
            }
        }
        .formStyle(.grouped)
        .onDisappear { stopRecording() }
    }

    /// 录制按钮：平时显示当前快捷键，录制中显示提示并高亮。
    private var recorderButton: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(isRecording ? "按下组合键…" : settings.hotkey.displayString)
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 108)
                .padding(.vertical, 3)
                .padding(.horizontal, 10)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .accentColor : nil)
        .overlay {
            if isRecording {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
    }

    private func shortcutRow(_ keys: String, _ title: String) -> some View {
        LabeledContent(title) {
            Text(keys)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        message = nil
        // 录制期间先注销全局快捷键，否则按到当前组合键会被直接吞掉，录不进来
        HotKeyCenter.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {
                message = "已取消"
                stopRecording()
                return nil
            }
            if let shortcut = Shortcut(event: event), shortcut.isValid {
                settings.hotkey = shortcut
                message = "已更新为 \(shortcut.displayString)"
                stopRecording()
                return nil
            }
            message = "这个按键不能作为全局快捷键，请加上 ⌘、⌥ 或 ⌃"
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording || monitor != nil else { return }
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        coordinator.applyHotKey()
    }
}

// MARK: - 关于

struct AboutSettings: View {
    @Environment(AppCoordinator.self) private var coordinator

    @State private var usage = 0
    @State private var isConfirmingErase = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Clip")
                            .font(.system(size: 15, weight: .semibold))
                        Text("版本 \(Bundle.main.clipVersion)（\(Bundle.main.clipBuild)）")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("原生、轻量的 macOS 剪贴板历史管理器")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
            }

            Section("存储") {
                LabeledContent("记录条数") {
                    Text("\(coordinator.store.items.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                LabeledContent("磁盘占用") {
                    Text(ClipItem.byteText(usage))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                LabeledContent("数据目录") {
                    Button("打开") {
                        NSWorkspace.shared.activateFileViewerSelecting([ClipStorage.shared.rootURL])
                    }
                }
            }

            Section {
                Button("清空全部数据…", role: .destructive) {
                    isConfirmingErase = true
                }
            } footer: {
                Text("会删除全部历史记录与图片文件，此操作无法撤销。固定的条目也会一并删除。")
            }
        }
        .formStyle(.grouped)
        .task { usage = await coordinator.store.diskUsage() }
        .confirmationDialog("确定要清空全部数据吗？", isPresented: $isConfirmingErase, titleVisibility: .visible) {
            Button("清空全部数据", role: .destructive) {
                Task {
                    await coordinator.store.eraseEverything()
                    // 缩略图/预览图缓存的键是 blob 文件名，清空后必须一起清，
                    // 否则已删除的图片还会从缓存里显示出来
                    ImageCache.shared.clear()
                    coordinator.store.showToast("已清空全部数据", symbol: "trash.fill")
                    usage = await coordinator.store.diskUsage()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("全部历史记录与图片文件都会被删除，且无法恢复。")
        }
    }
}

extension Bundle {
    var clipVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var clipBuild: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }
}
