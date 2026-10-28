import AppKit
import SwiftUI

/// 历史列表中的一行。
struct ClipRowView: View {
    @Environment(AppCoordinator.self) private var coordinator

    let item: ClipItem
    let isSelected: Bool
    let showSource: Bool
    let rowHeight: CGFloat

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 11) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                // 搜索命中的片段高亮：用户不用再逐字比对「为什么这一条被命中」。
                Text(SearchHighlight.attributed(item.title, keywords: coordinator.store.highlightKeywords))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(item.kind == .link || item.kind == .file ? .middle : .tail)
                subtitle
            }
            Spacer(minLength: 6)
            trailing
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight)
        .background(background)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .onTapGesture(perform: handleTap)
        .contextMenu { menu }
        .animation(.snappy(duration: 0.16), value: isSelected)
    }

    /// 单击立即选中；两次单击落在系统双击间隔内则按双击处理（粘贴）。
    ///
    /// 这里刻意不用 `.onTapGesture(count: 2)`：SwiftUI 会为它装上一个「需要两次点击」
    /// 的手势识别器，而 AppKit 的手势识别器在得出结论之前会**扣住主键鼠标事件**。
    /// 「是不是双击」要等双击间隔过去才有结论，于是整行的单击都被一起扣住——
    /// 连行尾的删除／固定按钮也跑不掉（实测延迟约等于 `NSEvent.doubleClickInterval`，
    /// 默认 0.5s，就是「点了半秒才选中」的来源）。
    /// 现在只用单击手势（识别即触发，不等待），双击由时间判定补上，语义不变。
    private func handleTap() {
        // 双击判定状态存在协调者上，不是每行自己的 @State：
        // 每行各记一份时，「点 A、再快速点 B」会让 B 用自己上次被点的时间
        // 误判成双击（两次点不同行也一样会命中），没怎么扫过列表的用户就会
        // 因为随手两下点击就把某一条直接粘到前台应用里。
        let now = Date()
        if let last = coordinator.lastTap,
           last.id == item.id,
           now.timeIntervalSince(last.at) <= NSEvent.doubleClickInterval {
            coordinator.lastTap = nil
            coordinator.paste(item)
        } else {
            coordinator.lastTap = (id: item.id, at: now)
            coordinator.store.selectedID = item.id
        }
    }

    // MARK: 内容

    @ViewBuilder
    private var leading: some View {
        switch item.kind {
        case .image:
            if let image = ImageCache.shared.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 46, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            } else {
                KindTile(kind: .image)
            }
        case .color:
            if let color = ColorValue.parse(item.text ?? "") {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: color))
                    .frame(width: 34, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
                    )
            } else {
                KindTile(kind: .color)
            }
        default:
            KindTile(kind: item.kind)
        }
    }

    private var subtitle: some View {
        HStack(spacing: 5) {
            Text(item.kind.title)
            Text("·")
            // 走 store 的缓存版本：文本条目的字符/行数统计是 O(全文长度)，
            // 而这一行在悬停、选中、滚动时都会重绘。
            Text(coordinator.store.detail(for: item))
            if showSource, let source = item.sourceName {
                Text("·")
                // 应用图标比名字更快被认出来；取不到图标（例如来源应用已卸载）时
                // 只显示文字，绝不为了一个图标去阻塞或占位。
                if let icon = SourceAppIcon.icon(forBundleID: item.sourceBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text(source)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 7) {
            if item.useCount > 1 {
                Text("×\(item.useCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
            }
            Text(item.relativeTime)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize()
            if isHovering {
                Button {
                    coordinator.store.togglePin(item.id)
                } label: {
                    Image(systemName: item.isPinned ? "pin.slash" : "pin")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(item.isPinned ? L("取消固定") : L("固定"))

                Button {
                    coordinator.store.remove(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L("删除"))
            }
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(fillColor)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
                }
            }
    }

    private var fillColor: Color {
        if isSelected { return Color.accentColor.opacity(0.24) }
        return isHovering ? Color.primary.opacity(0.06) : Color.clear
    }

    // MARK: 右键菜单

    @ViewBuilder
    private var menu: some View {
        Button(L("粘贴")) { coordinator.paste(item) }
        Button(L("粘贴为纯文本")) { coordinator.paste(item, plainText: true) }
        Button(L("仅复制")) { coordinator.copy(item) }
        Divider()
        Button(item.isPinned ? L("取消固定") : L("固定")) { coordinator.store.togglePin(item.id) }
        switch item.kind {
        case .link:
            if let url = item.linkURL {
                Button(L("打开链接")) { NSWorkspace.shared.open(url) }
            }
        case .file:
            if let path = item.filePaths?.first {
                Button(L("在访达中显示")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                Button(L("复制路径")) { coordinator.copyString(item.text ?? "") }
            }
        case .color:
            if let color = ColorValue.parse(item.text ?? "") {
                Button(L("复制 Hex")) { coordinator.copyString(color.clipHexString) }
                Button(L("复制 SwiftUI Color")) { coordinator.copyString(color.clipSwiftUIColorCode) }
            }
        case .image:
            Button(L("复制图片")) { coordinator.copy(item) }
        case .text:
            EmptyView()
        }
        Divider()
        Button(L("删除"), role: .destructive) { coordinator.store.remove(item.id) }
    }
}
