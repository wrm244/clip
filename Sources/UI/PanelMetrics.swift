import CoreGraphics

/// 面板排版的唯一来源：SwiftUI 布局与窗口尺寸都读这里，
/// 保证两边算出来的高度一致（否则窗口和内容会错位）。
enum PanelMetrics {
    /// 面板圆角。SwiftUI 裁剪和 NSGlassEffectView 必须用同一个值，
    /// 否则两者形状不完全重合，边角会露出一条方形描边。
    static let cornerRadius: CGFloat = 22

    /// 内容区内边距（8pt 网格上取 10，视觉更紧凑）
    static let padding: CGFloat = 10
    static let searchHeight: CGFloat = 32
    static let searchRadius: CGFloat = 8
    static let chipHeight: CGFloat = 24
    /// 药丸之间的间距。必须明显大于 GlassEffectContainer 的融合距离，
    /// 否则相邻的液态玻璃形状会互相融合，看起来就是「粘在一起」。
    static let chipSpacing: CGFloat = 8
    /// 玻璃形状互相融合的距离阈值，取值远小于 chipSpacing。
    static let glassBlendSpacing: CGFloat = 3
    static let headerSpacing: CGFloat = 8
    static let listRowSpacing: CGFloat = 2
    static let listPadding: CGFloat = 6
    static let footerHeight: CGFloat = 34
    static let separator: CGFloat = 1

    /// 展开预览时右侧新增的宽度
    static let previewWidth: CGFloat = 320
    /// 预览展开时左侧列表至少要保持的宽度
    static let minListWidth: CGFloat = 400

    // 窗口高度不在这里算：它是用户设定的固定值（ClipSettings.panelHeight），
    // 不随条目数收缩，否则呼出/收起时窗口会上下跳。

    /// 窗口宽度：展开预览时向右加宽，列表宽度不变。
    static func panelWidth(listWidth: CGFloat, previewing: Bool) -> CGFloat {
        previewing ? max(listWidth, minListWidth) + separator + previewWidth : listWidth
    }
}
