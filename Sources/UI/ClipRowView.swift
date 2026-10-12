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
                Text(item.title)
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
        .onTapGesture(count: 2) { coordinator.paste(item) }
        .onTapGesture { coordinator.store.selectedID = item.id }
        .contextMenu { menu }
        .animation(.snappy(duration: 0.16), value: isSelected)
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
                .help(item.isPinned ? "取消固定" : "固定")

                Button {
                    coordinator.store.remove(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("删除")
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
        Button("粘贴") { coordinator.paste(item) }
        Button("粘贴为纯文本") { coordinator.paste(item, plainText: true) }
        Button("仅复制") { coordinator.copy(item) }
        Divider()
        Button(item.isPinned ? "取消固定" : "固定") { coordinator.store.togglePin(item.id) }
        switch item.kind {
        case .link:
            if let url = URL(string: item.text ?? "") {
                Button("打开链接") { NSWorkspace.shared.open(url) }
            }
        case .file:
            if let path = item.filePaths?.first {
                Button("在访达中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                Button("复制路径") { coordinator.copyString(item.text ?? "") }
            }
        case .color:
            if let color = ColorValue.parse(item.text ?? "") {
                Button("复制 Hex") { coordinator.copyString(color.clipHexString) }
                Button("复制 SwiftUI Color") { coordinator.copyString(color.clipSwiftUIColorCode) }
            }
        case .image:
            Button("复制图片") { coordinator.copy(item) }
        case .text:
            EmptyView()
        }
        Divider()
        Button("删除", role: .destructive) { coordinator.store.remove(item.id) }
    }
}
