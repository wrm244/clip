import AppKit
import SwiftUI

/// 菜单栏下拉面板。
///
/// 由 MenuBarPanelController 呈现在状态项的「展开界面」里
/// （macOS 27 的 NSStatusItemExpandedInterfaceDelegate 会话，不是 SwiftUI 的 MenuBarExtra，
/// 也不是 NSPopover）：面板外观用 NSGlassEffectView 铺底，按钮和菜单点击可靠。
///
/// 尺寸固定，底部用 Spacer 顶住：条目多少都不会把底部的三个动作挤出去。
struct MenuBarView: View {
    static let size = NSSize(width: 340, height: 336)

    /// 底栏三格之间的间隔。
    private static let footerSpacing: CGFloat = 4
    /// 面板内容区四周的内边距（`body` 的 `.padding`）。
    private static let contentPadding: CGFloat = 12

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(ClipStore.self) private var store
    @Environment(ClipSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            openButton
                .padding(.top, 12)
            separator
                .padding(.vertical, 10)
            recent
            Spacer(minLength: 0)
            separator
                .padding(.vertical, 10)
            footerBar
        }
        .padding(Self.contentPadding)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "clipboard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text("Clip")
                    .font(.system(size: 13, weight: .semibold))
                Text(L("%ld 条历史 · %@ 呼出", store.items.count, settings.hotkey.displayString))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Bindable(settings).isMonitoringEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(settings.isMonitoringEnabled ? L("暂停记录剪贴板") : L("开始记录剪贴板"))
        }
        .frame(height: 34)
    }

    // MARK: 主操作

    private var openButton: some View {
        Button {
            MenuBarPanel.dismiss?()
            Task { @MainActor in coordinator.showPanel() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.on.rectangle.angled")
                Text(L("打开剪贴板历史"))
                Spacer(minLength: 6)
                Text(settings.hotkey.displayString)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }

    // MARK: 最近记录

    private var recent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("最近"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.bottom, 2)

            if store.items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "tray")
                    Text(L("还没有任何记录"))
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .frame(height: 26)
            } else {
                ForEach(store.items.prefix(5)) { item in
                    MenuBarRow(item: item) {
                        MenuBarPanel.dismiss?()
                        coordinator.paste(item)
                    }
                }
            }
        }
    }

    // MARK: 底部动作

    private var footerBar: some View {
        // 三个动作共用系统的 accessoryBarAction 样式：原生悬停 / 按下反馈、原生文字色。
        // 宽度靠 `.frame(maxWidth: .infinity)` 自动三等分（见 BarActionLabel）。
        HStack(spacing: Self.footerSpacing) {
            Button {
                MenuBarPanel.dismiss?()
                Task { @MainActor in coordinator.openSettings() }
            } label: {
                BarActionLabel(title: L("设置"), symbol: "gearshape")
            }
            .buttonStyle(.accessoryBarAction)
            .frame(maxWidth: .infinity)
            .help(L("打开设置"))

            // 「清空」是下拉：用普通 Button + 原生 NSMenu（MenuActionButton），
            // 而不是 SwiftUI 的 Menu。后者的底色由内部按钮按内容的理想宽度绘制，
            // 会明显比两侧窄一圈；而且 `.menuIndicator(.hidden)` 之后连标签里自画的
            // chevron 也会被一起丢掉——「不统一样式 + 没有标识」就是这么来的。
            // 换成和两侧同一个 `.accessoryBarAction` 按钮 + 自弹菜单，三格的底色 /
            // 高度 / 文字色都由同一套样式决定，天然一致。
            MenuActionButton {
                let target = MenuActionTarget()
                let menu = NSMenu()
                menu.addItem(target.item(L("清空未固定记录")) {
                    coordinator.clearHistory(keepingPinned: true)
                    MenuBarPanel.dismiss?()
                })
                menu.addItem(target.item(L("清空全部记录"), isDestructive: true) {
                    coordinator.clearHistory(keepingPinned: false)
                    MenuBarPanel.dismiss?()
                })
                menu.addItem(.separator())
                menu.addItem(target.item(L("在访达中显示数据目录")) {
                    NSWorkspace.shared.activateFileViewerSelecting([ClipStorage.shared.rootURL])
                    MenuBarPanel.dismiss?()
                })
                return menu
            } label: {
                BarActionLabel(
                    title: L("清空"),
                    symbol: "trash",
                    trailingSymbol: "chevron.down"
                )
            }
            .frame(maxWidth: .infinity)
            .help(L("清空记录或打开数据目录"))

            Button {
                NSApp.terminate(nil)
            } label: {
                BarActionLabel(
                    title: L("退出"),
                    symbol: "power",
                    isDestructive: true
                )
            }
            .buttonStyle(.accessoryBarAction)
            .frame(maxWidth: .infinity)
            .help(L("退出 Clip"))
        }
        .frame(height: 26)
    }
}

/// 菜单栏底部的动作按钮外观。设置 / 清空 / 退出共用同一套排版。
///
/// 悬停 / 按下反馈交给系统的 `.accessoryBarAction`（见 `footerBar`），
/// 这里只负责图标 + 文案的排版与语义色，避免两套高亮叠在一起。
///
/// 宽度用 `maxWidth: .infinity` 弹性撑满：**不能写死等分宽度**，因为按钮样式
/// 自己还会在左右各加一圈内边距，写死会让三个按钮的总宽超过内容区，把外层
/// `padding` 顶掉（表现就是底部三格贴到面板左右边缘）。
private struct BarActionLabel: View {
    let title: String
    let symbol: String
    /// 挂在文案右侧的补充符号（「清空」自画的菜单箭头）。
    var trailingSymbol: String? = nil
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            if let trailingSymbol {
                Image(systemName: trailingSymbol)
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.55)
            }
        }
        .foregroundStyle(isDestructive ? Color.red : Color.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .contentShape(.rect)
    }
}

/// 外观和普通 `.accessoryBarAction` 按钮完全一致，点击弹出原生 `NSMenu`。
///
/// 为什么不直接用 SwiftUI 的 `Menu`：它跟 `.accessoryBarAction` 组合时，底色由
/// 内部按钮按内容的理想宽度绘制（比两侧窄一圈），标签里自画的 `chevron.down`
/// 也会被丢掉。换成普通 `Button` 自己弹 `NSMenu`，三格就完全同款了。
private struct MenuActionButton<Label: View>: View {
    let makeMenu: () -> NSMenu
    @ViewBuilder var label: () -> Label
    /// 按钮背后的 NSView，用来给 NSMenu 定位（弹出位置跟着按钮走）。
    @State private var anchor: NSView?

    var body: some View {
        Button {
            guard let anchor, anchor.window != nil else { return }
            // 以按钮左下角为锚点：菜单从按钮下方展开。
            makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: anchor)
        } label: {
            label()
        }
        .buttonStyle(.accessoryBarAction)
        .background(NSViewAnchor { anchor = $0 })
    }
}

/// 把按钮背后的 NSView 交出来，供 `NSMenu.popUp` 当锚点。
private struct NSViewAnchor: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // 延迟到本轮更新之后再回写 @State，避免"更新期间修改状态"。
        Task { @MainActor in onResolve(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// 用闭包当 target/action 的菜单项（`NSMenuItem` 只能走 target/action）。
///
/// 每个菜单配一个 target：handler 数组挂在它身上，item 的 `tag` 是下标。
/// `NSMenuItem.target` 是弱引用，所以再把 target 存进每个 item 的 `representedObject`
/// （强引用）保活——菜单在、item 就在，target 不会被提前释放。
@MainActor
private final class MenuActionTarget: NSObject {
    private var handlers: [() -> Void] = []

    func item(_ title: String, isDestructive: Bool = false, handler: @escaping () -> Void) -> NSMenuItem {
        let index = handlers.count
        handlers.append(handler)

        let item = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: "")
        item.target = self
        item.tag = index
        item.representedObject = self
        if isDestructive {
            item.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.menuFont(ofSize: 0),
                    .foregroundColor: NSColor.systemRed,
                ]
            )
        }
        return item
    }

    @objc private func fire(_ sender: NSMenuItem) {
        guard handlers.indices.contains(sender.tag) else { return }
        handlers[sender.tag]()
    }
}

/// 菜单栏里的最近记录行。
private struct MenuBarRow: View {
    let item: ClipItem
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: item.kind.symbolName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(item.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(item.relativeTime)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .frame(height: 27)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.09) : Color.clear)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
