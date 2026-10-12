import AppKit
import SwiftUI

// MARK: - 玻璃质感修饰

extension View {
    /// 统一使用 Liquid Glass（macOS 26 引入，macOS 27 支持交互反馈）。
    func clipGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(ClipGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }
}

/// 统一的玻璃样式。
/// 系统打开「降低透明度」时不使用玻璃，改成不透明底色——
/// HIG：请为「降低透明度」提供一个实心背景，不要强行保留半透明材质。
private struct ClipGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(shape.fill(tint ?? Color(nsColor: .controlBackgroundColor)))
        } else {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        }
    }
}

// MARK: - 分隔线

/// 分隔线。打开「增强对比度」时自动加深。
/// HIG：开启「增强对比度」时要提供对比度更高的配色。
struct ClipSeparator: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(contrast == .increased ? 0.22 : 0.08))
            .frame(height: PanelMetrics.separator)
    }
}

// MARK: - 面板底色

/// 面板的兜底底色：只有打开「降低透明度」时才铺一层不透明背景，替掉背后的玻璃。
struct PanelBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}

// MARK: - 分类药丸

struct FilterChip: View {
    let filter: ClipFilter
    let count: Int
    let isSelected: Bool
    /// 窄弹窗下只留图标和数量，省出宽度。
    var compact: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: filter.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                if !compact {
                    Text(filter.title)
                        .font(.system(size: 12, weight: .medium))
                }
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .opacity(isSelected ? 0.85 : 0.6)
                }
            }
            .padding(.horizontal, compact ? 8 : 10)
            .frame(height: PanelMetrics.chipHeight)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .clipGlass(.capsule, tint: isSelected ? Color.accentColor : nil, interactive: true)
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.18), value: isSelected)
    }
}

// MARK: - 键盘提示

struct KeyHint: View {
    let keys: String
    var label: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.09))
                )
            if let label {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 类型图标

struct KindTile: View {
    let kind: ClipKind
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
    }
}

// MARK: - 提示条

struct ToastView: View {
    let toast: ClipToast

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.symbol)
                .font(.system(size: 12, weight: .semibold))
            Text(toast.text)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .clipGlass(.capsule)
        // 深色外观下黑色阴影几乎不可见，需要更深一点才有"浮起来"的层次
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.18), radius: 14, y: 5)
    }
}

// MARK: - 空状态

struct EmptyHint: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
