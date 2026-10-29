import SwiftUI

/// iOS 18 的缩放转场：点哪个卡片，那个卡片就长大成整页；返回时缩回原处。
///
/// 这套接口是 iOS 18.0 才有的：
///   - 来源视图：`.matchedTransitionSource(id:in:)`
///   - 目标页面：`.navigationTransition(.zoom(sourceID:in:))`
///
/// 项目最低支持 iOS 17，所以这里用 `#available` 包一层：
/// iOS 18 上是苹果原生那种「弹出放大」的效果，
/// iOS 17 上退回系统默认的推入动画 —— 不崩、也不影响编译。
extension View {

    /// 标记「这一块是起点」。点它之后，它会朝目标页的方向放大。
    @ViewBuilder
    func zoomSource(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// 标记「这一页是终点」。它从对应的起点卡片放大而来，返回时缩回去。
    @ViewBuilder
    func zoomDestination(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
