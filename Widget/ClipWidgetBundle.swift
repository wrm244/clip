import SwiftUI
import WidgetKit

/// 小组件扩展的入口。
///
/// 桌面小组件是独立沙盒进程，不能直接打开主 App 的 SwiftData 库，
/// 也无法使用 App Group（免签构建下该权限会被系统忽略）。
/// 所以主 App 把最近历史导出一份只读快照，小组件用 temporary-exception
/// 只读权限读取它——详见 `WidgetFeed` 与 `Widget/ClipWidget.entitlements`。
@main
struct ClipWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClipWidget()
    }
}
