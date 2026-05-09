import Foundation
import WinAppSDK
import WinUI

/// Window context exposed to modules.
public struct WindowContext {
    let owner: MainWindow

    public func pickFolder(_ handler: @escaping (String) -> Void) {
        Task { @MainActor in
            let picker = FolderPicker(owner.appWindow.id)
            guard let asyncResult = try? picker.pickSingleFolderAsync() else { return }
            guard let result = try? await asyncResult.get() else { return }

            await MainActor.run {
                handler(result.path)
            }
        }
    }

    /// 用指定模式打开页面。`mode` 默认 `.inplace`（当前 Tab 内导航）。
    /// 模块可显式传 `.newTab` / `.newTabBackground` / `.newWindow` 选择行为。
    public func navigate(
        to page: Page,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) {
        owner.navigate(to: page, mode: mode, transitionInfoOverride: transitionInfoOverride)
    }

    /// URL 形式的导航；返回 `false` 表示没有任何模块识别该 URL。
    @discardableResult
    public func navigate(
        to url: URL,
        mode: NavigationOpenMode = .inplace,
        transitionInfoOverride: NavigationTransitionInfo? = nil
    ) -> Bool {
        return owner.navigate(to: url, mode: mode, transitionInfoOverride: transitionInfoOverride)
    }
}
