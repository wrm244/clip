import AppKit
import SwiftUI

/// 面板右侧的预览窗格。
struct PreviewPane: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: ClipItem?

    /// 图片预览的悬停态：出现「可预览」角标和更亮的描边。
    @State private var imageHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item {
                header(for: item)
                separator
                ScrollView {
                    detail(for: item)
                        .padding(12)
                        .frame(width: Self.scrollContentWidth, alignment: .leading)
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
        // 悬停态挂在 PreviewPane 上，切换条目不会重建它；不重置的话新图会带着上一张的
        // 角标 / 高亮描边，直到鼠标移出再进入。
        .onChange(of: item?.id) { _, _ in imageHovering = false }
    }

    private var separator: some View { ClipSeparator() }

    /// 滚动内容的固定宽度：预览窗宽 − 经典式滚动条要占掉的宽度（覆盖式浮在内容上，不占）。
    ///
    /// 这里必须把宽度**钉死**，不能给内容 `maxWidth: .infinity` 随视口走：
    /// 图片按宽度等比缩放，而经典式滚动条出现／消失会改变内容区宽度（AppKit 会重新
    /// 排布 NSScrollView），于是形成死循环——滚动条出现 → 内容区变窄 → 图变矮 →
    /// 内容不再超高 → 滚动条消失 → 内容区变宽 → 图变高 → 再度超高 → 滚动条再现……
    /// 每帧往返一次，表现就是滚动条疯狂闪烁、图片尺寸来回闪跳。
    /// 宽度钉死后，内容高度与滚动条的有无彻底解耦，两种滚动条样式下循环都不成立。
    private static var scrollContentWidth: CGFloat {
        let reserve: CGFloat = NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            : 0
        return PanelMetrics.previewWidth - reserve
    }

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
            textDetail(item.text ?? "")
        }
    }

    /// 文本预览上限（字符）。
    ///
    /// 单条文本上限 120KB，整段交给 SwiftUI / TextKit 布局会长时间占住主线程。
    /// 预览窗只需要看个大概，超出部分截断并提示；完整内容仍可通过「复制 / 粘贴」取出。
    private static let textPreviewLimit = 8_000

    @ViewBuilder
    private func textDetail(_ text: String) -> some View {
        let truncated = text.count > Self.textPreviewLimit
        VStack(alignment: .leading, spacing: 8) {
            Text(truncated ? String(text.prefix(Self.textPreviewLimit)) : text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            if truncated {
                Text(L("文本较长，仅预览前 %ld 个字符", Self.textPreviewLimit))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func imageDetail(for item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = ImageCache.shared.preview(for: item) {
                // 整张图就是一个按钮：点一下用系统 Quick Look 打开（自带 Live Text，可选中 / 复制图中文字）。
                Button {
                    coordinator.quickLook.present(item)
                } label: {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(imageShape)
                        .overlay(
                            imageShape
                                .stroke(Color.primary.opacity(imageHovering ? 0.3 : 0.12), lineWidth: 0.5)
                        )
                        .overlay(alignment: .bottomTrailing) { zoomBadge }
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .onHover { imageHovering = $0 }
                .animation(reduceMotion ? nil : .smooth(duration: 0.15), value: imageHovering)
                .help(L("点击预览"))
                .accessibilityLabel(L("预览图片"))
            }
            metaRow(L("尺寸"), "\(item.pixelWidth ?? 0) × \(item.pixelHeight ?? 0)")
            metaRow(L("体积"), ClipItem.byteText(item.byteCount))
        }
    }

    private var imageShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    /// 悬停时右下角出现的「可预览」角标。不参与命中测试，点击穿透到整张图。
    private var zoomBadge: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(7)
            .clipGlass(.circle)
            .padding(8)
            .opacity(imageHovering ? 1 : 0)
            .allowsHitTesting(false)
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
