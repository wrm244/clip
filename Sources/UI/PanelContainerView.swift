import AppKit

/// 面板窗口的内容容器，只负责一件事：面板的形状。
///
/// 用 macOS 27 的原生圆角 API（NSView.cornerConfiguration）声明形状，
/// 系统解析出 effectiveCornerRadii 后回调 viewDidChangeEffectiveCornerRadii()，
/// 我们据此设置 layer 并裁剪子视图。
///
/// 为什么需要多这一层：
/// NSGlassEffectView 会为自己画一圈柔和的阴影，而它铺满整个窗口，
/// 于是这圈阴影只能落在窗口四角——也就是圆角之外的空白区域。
/// 屏幕上看起来就是「圆角外面多出来一个方形边框」。
/// 容器按原生圆角把四角裁掉之后就没有了；
/// 同时窗口的 alpha 变成干净的圆角矩形，AppKit 的窗口阴影也能跟随这个形状。
final class PanelContainerView: NSView {

    /// 面板圆角半径。改动后重新向系统解析一次。
    var cornerRadius: CGFloat = PanelMetrics.cornerRadius {
        didSet {
            guard cornerRadius != oldValue else { return }
            invalidateCornerConfiguration()
            applyCornerShape()
        }
    }

    // MARK: 原生圆角

    override var cornerConfiguration: NSViewCornerConfiguration? {
        .uniformCorners(radius: .fixed(cornerRadius))
    }

    override func viewDidChangeEffectiveCornerRadii() {
        applyCornerShape()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        invalidateCornerConfiguration()
        applyCornerShape()
    }

    override func layout() {
        super.layout()
        applyCornerShape()
    }

    /// 把系统解析出来的圆角应用到 layer。
    /// 用 mask 而不是 masksToBounds：前者只裁剪内容，layer 自己的阴影还能照常画。
    private func applyCornerShape() {
        let radius = effectiveCornerRadii?.topLeft ?? cornerRadius
        guard radius > 0, !bounds.isEmpty else { return }
        wantsLayer = true
        guard let layer else { return }
        layer.cornerCurve = .continuous
        let path = CGPath(
            roundedRect: bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        let mask = CAShapeLayer()
        mask.path = path
        layer.mask = mask
        layer.shadowPath = path
    }
}
