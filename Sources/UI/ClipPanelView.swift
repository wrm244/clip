import AppKit
import SwiftUI

/// 快速呼出面板的根视图。
///
/// 排版遵循 Apple HIG：
/// - 8pt 网格、统一间距，元素对齐便于快速扫视
/// - 内容层不使用 Liquid Glass（玻璃只留给面板本身和临时提示条）
/// - 行内容简短，避免过高的行
struct ClipPanelView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(ClipStore.self) private var store
    @Environment(ClipSettings.self) private var settings

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var searchFocused: Bool

    /// 列表宽度。展开预览时至少保留 PanelMetrics.minListWidth，
    /// 口径必须和 PanelMetrics.panelWidth 一致，否则左侧会多出空白。
    private var listWidth: Double {
        store.previewVisible ? max(settings.panelWidth, PanelMetrics.minListWidth) : settings.panelWidth
    }

    /// 宽度不够时分类只显示图标。
    private var isCompact: Bool { listWidth < 620 }

    var body: some View {
        VStack(spacing: 0) {
            header
            separator
            HStack(spacing: 0) {
                list
                    .frame(width: listWidth)
                if store.previewVisible {
                    separator
                    // 不加任何 transition：窗口尺寸是瞬间变化的，
                    // 内容再做淡入/位移就会和窗口不同步，看起来就是列表在回弹。
                    PreviewPane(item: store.selectedItem)
                        .frame(width: PanelMetrics.previewWidth)
                }
            }
            .frame(maxHeight: .infinity)
            separator
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 动画只挂在提示条自己身上；根视图上没有任何动画修饰符，
        // 避免列表/滚动的布局变化被顺带动画化。
        .overlay(alignment: .bottom) {
            toastLayer
                .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: store.toast)
        }
        .onChange(of: coordinator.panel.isVisible) { _, visible in
            if visible { focusSearch() }
        }
        .onAppear { focusSearch() }
    }

    private var separator: some View { ClipSeparator() }

    // MARK: 头部（搜索 + 分类）

    private var header: some View {
        VStack(spacing: PanelMetrics.headerSpacing) {
            searchField
            filterRow
        }
        .padding(.horizontal, PanelMetrics.padding)
        .padding(.top, PanelMetrics.padding)
        .padding(.bottom, PanelMetrics.headerSpacing)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                // 占位文字自己画，不用 TextField 自带的：
                // AppKit 的占位色是在绘制时按"当前外观"取的，而玻璃容器会跟着背后内容
                // 自适应翻转明暗，于是这行字会在黑白之间来回跳。
                // 换成 SwiftUI 的 Text 走环境语义色，就和左边的放大镜图标同一套渲染，稳定。
                if store.searchText.isEmpty {
                    Text("搜索剪贴板历史")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
                TextField("", text: Bindable(store).searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                    .accessibilityLabel("搜索剪贴板历史")
            }
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
        }
        .padding(.horizontal, 9)
        .frame(height: PanelMetrics.searchHeight)
        .background(
            RoundedRectangle(cornerRadius: PanelMetrics.searchRadius, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
    }

    private var filterRow: some View {
        HStack(spacing: 0) {
            // 液态玻璃放在 GlassEffectContainer 里才会正确采样；
            // 融合距离 (3pt) 远小于药丸间距 (8pt)，所以它们不会粘成一团。
            GlassEffectContainer(spacing: PanelMetrics.glassBlendSpacing) {
                HStack(spacing: PanelMetrics.chipSpacing) {
                    ForEach(ClipFilter.allCases) { filter in
                        FilterChip(
                            filter: filter,
                            count: store.filterCounts[filter] ?? 0,
                            isSelected: store.filter == filter,
                            compact: isCompact
                        ) {
                            store.filter = filter
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 列表

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: PanelMetrics.listRowSpacing) {
                    ForEach(store.visibleItems) { item in
                        ClipRowView(
                            item: item,
                            isSelected: item.id == store.selectedID,
                            showSource: settings.showSourceApp,
                            rowHeight: settings.density.rowHeight
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal, PanelMetrics.listPadding)
                .padding(.vertical, PanelMetrics.listPadding)
            }
            .onChange(of: store.selectedID) { _, newValue in
                guard let newValue else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.15)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if store.visibleItems.isEmpty {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        let searching = !store.searchText.trimmingCharacters(in: .whitespaces).isEmpty
        return EmptyHint(
            title: searching ? "没有匹配的结果" : "暂无剪贴板历史",
            message: searching ? "换个关键词试试" : "复制任意内容后，它会出现在这里",
            symbol: searching ? "magnifyingglass" : "clipboard"
        )
    }

    // MARK: 底部状态栏

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(store.visibleItems.count) 项")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button {
                settings.isMonitoringEnabled.toggle()
            } label: {
                Image(systemName: settings.isMonitoringEnabled ? "pause.circle" : "play.circle.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .foregroundStyle(settings.isMonitoringEnabled ? Color.secondary : Color.orange)
            .help(settings.isMonitoringEnabled ? "暂停记录" : "继续记录")

            // 没授权时一直显示，用户点一下就能去系统设置，不会"按了回车没反应"。
            if settings.autoPaste, !coordinator.paste.isTrusted {
                Button {
                    coordinator.paste.requestAccess()
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .foregroundStyle(.orange)
                .help("自动粘贴需要辅助功能权限，点此授权")
            }

            Spacer(minLength: 6)

            KeyHint(keys: "↵", label: "粘贴")
            if isCompact {
                KeyHint(keys: "esc", label: "关闭")
            } else {
                KeyHint(keys: "⌥↵", label: "纯文本")
                KeyHint(keys: "→", label: "预览")
                KeyHint(keys: "⌘P", label: "固定")
                KeyHint(keys: "⌘⌫", label: "删除")
            }

            Spacer(minLength: 6)

            Button {
                coordinator.panel.setPreview(!store.previewVisible)
            } label: {
                Image(systemName: store.previewVisible ? "sidebar.right" : "sidebar.squares.right")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .foregroundStyle(store.previewVisible ? Color.accentColor : Color.secondary)
            .help("切换预览面板 ⌘Y")

            Button {
                coordinator.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .foregroundStyle(.secondary)
            .help("设置 ⌘,")
        }
        .padding(.horizontal, PanelMetrics.padding)
        .frame(height: PanelMetrics.footerHeight)
    }

    // MARK: 提示条

    @ViewBuilder
    private var toastLayer: some View {
        if let toast = store.toast {
            ToastView(toast: toast)
                .padding(.bottom, PanelMetrics.footerHeight + 10)
                .allowsHitTesting(false)
        }
    }

    private func focusSearch() {
        searchFocused = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            searchFocused = true
        }
    }
}
