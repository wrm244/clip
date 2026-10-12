import AppKit
import SwiftUI

/// 面板右侧的预览窗格。
struct PreviewPane: View {
    @Environment(AppCoordinator.self) private var coordinator
    let item: ClipItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item {
                header(for: item)
                separator
                ScrollView {
                    detail(for: item)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // 每条从顶部开始看：不给 id 的话 ScrollView 会沿用上一条的滚动位置
                // （只有内容类型变了才会自己归零），长文本 → 短文本、大图 → 小图
                // 时会停在中段，看着就像预览窗「跳了一下」。
                .id(item.id)
                separator
                actions(for: item)
            } else {
                EmptyHint(title: L("未选择条目"), message: L("在左侧选择一条记录即可查看详情"), symbol: "square.dashed")
            }
        }
        .frame(width: PanelMetrics.previewWidth)
        .frame(maxHeight: .infinity)
    }

    private var separator: some View { ClipSeparator() }

    // MARK: 头部

    private func header(for item: ClipItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(item.kind.title)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(item.relativeTime)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    // MARK: 内容

    @ViewBuilder
    private func detail(for item: ClipItem) -> some View {
        switch item.kind {
        case .image:
            imageDetail(for: item)
        case .color:
            colorDetail(for: item)
        case .file:
            fileDetail(for: item)
        case .link:
            linkDetail(for: item)
        case .text:
            Text(item.text ?? "")
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func imageDetail(for item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = ImageCache.shared.preview(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            }
            metaRow(L("尺寸"), "\(item.pixelWidth ?? 0) × \(item.pixelHeight ?? 0)")
            metaRow(L("体积"), ClipItem.byteText(item.byteCount))
        }
    }

    @ViewBuilder
    private func colorDetail(for item: ClipItem) -> some View {
        if let color = ColorValue.parse(item.text ?? "") {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: color))
                    .frame(height: 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                    )
                metaRow("HEX", color.clipHexString)
                metaRow("RGB", color.clipRGBDescription)
                metaRow("SwiftUI", color.clipSwiftUIColorCode)
            }
        } else {
            Text(item.text ?? "")
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func fileDetail(for item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(item.filePaths ?? [], id: \.self) { path in
                HStack(spacing: 7) {
                    Image(systemName: "doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text((path as NSString).lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text((path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func linkDetail(for item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.text ?? "")
                .font(.system(size: 12))
                .textSelection(.enabled)
            if let url = URL(string: item.text ?? "") {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(L("在浏览器中打开"), systemImage: "arrow.up.right.square")
                        .font(.system(size: 11))
                }
                .buttonStyle(.link)
            }
        }
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 操作区

    private func actions(for item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    coordinator.paste(item)
                } label: {
                    Label(L("粘贴"), systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular)

                Button {
                    coordinator.copy(item)
                } label: {
                    Label(L("复制"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.glass)
                .controlSize(.regular)
            }
            HStack(spacing: 8) {
                Button {
                    coordinator.store.togglePin(item.id)
                } label: {
                    Label(item.isPinned ? L("取消固定") : L("固定"), systemImage: item.isPinned ? "pin.slash" : "pin")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                if let source = item.sourceName {
                    Text(source)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
    }
}
