/// 导航打开模式 —— 调用 `WindowContext.navigate` / `MainWindow.navigate` 时指定。
///
/// - inplace：在当前选中 Tab 内导航（默认行为）
/// - newTab：打开为新 Tab 并切换过去
/// - newTabBackground：打开为新 Tab 但**不**切换过去（类似浏览器 Ctrl+click）
/// - newWindow：打开为新主窗口
public enum NavigationOpenMode: Sendable {
    case inplace
    case newTab
    case newTabBackground
    case newWindow
}
