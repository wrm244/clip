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
        .padding(12)
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
        // 三个动作共用系统的 accessoryBarAction 样式：原生悬停 / 按下反馈、
        // 原生文字色，三项观感天然一致，不再自己画悬停底色。
        HStack(spacing: 4) {
            Button {
                MenuBarPanel.dismiss?()
                Task { @MainActor in coordinator.openSettings() }
            } label: {
                BarActionLabel(title: L("设置"), symbol: "gearshape")
            }
            .buttonStyle(.accessoryBarAction)
            .help(L("打开设置"))
            .frame(maxWidth: .infinity)

            // 下拉菜单保留系统的菜单指示箭头（chevron），让「点开还有更多选项」一目了然。
            //
            // 用 menuStyle(.button) + buttonStyle，而不是已废弃的 .borderlessButton：
            // 后者会把标签强制画成默认控件文字色，无视 label 上的 foregroundStyle，
            // 于是「设置」是灰色、「清空」是深色，两者对不上。
            Menu {
                Button(L("清空未固定记录")) {
                    coordinator.clearHistory(keepingPinned: true)
                    MenuBarPanel.dismiss?()
                }
                Button(L("清空全部记录"), role: .destructive) {
                    coordinator.clearHistory(keepingPinned: false)
                    MenuBarPanel.dismiss?()
                }
                Divider()
                Button(L("在访达中显示数据目录")) {
                    NSWorkspace.shared.activateFileViewerSelecting([ClipStorage.shared.rootURL])
                    MenuBarPanel.dismiss?()
                }
            } label: {
                BarActionLabel(title: L("清空"), symbol: "trash")
            }
            .menuStyle(.button)
            .buttonStyle(.accessoryBarAction)
            .menuIndicator(.visible)
            .help(L("清空记录或打开数据目录"))
            .frame(maxWidth: .infinity)

            Button {
                NSApp.terminate(nil)
            } label: {
                BarActionLabel(title: L("退出"), symbol: "power", isDestructive: true)
            }
            .buttonStyle(.accessoryBarAction)
            .help(L("退出 Clip"))
            .frame(maxWidth: .infinity)
        }
        .frame(height: 26)
    }
}

/// 菜单栏底部的动作按钮外观。设置 / 清空 / 退出共用同一套排版。
///
/// 悬停 / 按下反馈交给系统的 `.accessoryBarAction`（见 `footerBar`），
/// 这里只负责图标 + 文案的排版与语义色，避免两套高亮叠在一起。
///
/// 注意：这里不能用 `.secondary`。下拉菜单的 `Menu` 标签会忽略
/// `foregroundStyle`，始终用默认控件文字色绘制；若两旁按钮单独用灰色，
/// 三者颜色就会对不上。统一用默认色（退出用红色）才一致。
private struct BarActionLabel: View {
    let title: String
    let symbol: String
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(isDestructive ? Color.red : Color.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .contentShape(.rect)
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
