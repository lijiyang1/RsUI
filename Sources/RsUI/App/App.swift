import Foundation
import WinUI
import RsHelper
import CRsUIJumpList

open class App: SwiftApplication {
    public static var context = AppContext.cli()

    let group: String
    let product: String
    let bundle: Bundle
    let moduleTypes: [Module.Type]

    public required convenience init() {
        self.init("SwiftWorks", "RsUI", .main, [])
    }

    public init(_ group: String, _ product: String, _ bundle: Bundle, _ moduleTypes: [Module.Type]) {
        self.group = group
        self.product = product
        self.bundle = bundle
        self.moduleTypes = moduleTypes

        super.init()
    }

    private var appUserModelID: String {
        // Stable across releases — taskbar uses this to identify the app for
        // both pinning and jump list lookup. Don't change once shipped.
        return "\(group).\(product)"
    }

    override open func onLaunched(_ args: WinUI.LaunchActivatedEventArgs) {
        // Need to init context after super.init() because some WinUI APIs require the application to be initialized
        App.context = AppContext.gui(group, product, bundle)
        App.context.modules = moduleTypes.map { $0.init() }

        registerTaskbarJumpList()

        let forceHome = parseForceHomeFromCommandLine(args)
        let mainWindow = forceHome ? MainWindow(forceHomeOnLaunch: true) : MainWindow()
        try! mainWindow.activate()
    }

    private func parseForceHomeFromCommandLine(_ args: WinUI.LaunchActivatedEventArgs) -> Bool {
        let flag = "--new-window"
        if CommandLine.arguments.contains(flag) {
            return true
        }
        // LaunchActivatedEventArgs.arguments is a space-joined string when the
        // process is activated through certain shell paths (jump list included).
        return args.arguments.split(separator: " ").contains { $0 == flag }
    }

    private func registerTaskbarJumpList() {
        // Swift String 转成以 null 结尾的宽字符数组，直接当 const wchar_t* 传给 C 桥接，
        // 省去逐参数嵌套 withCString。
        func wide(_ s: String) -> [UInt16] { Array(s.utf16) + [0] }

        let aumid = appUserModelID
        let aumidStatus = rs_set_app_user_model_id(wide(aumid))
        if aumidStatus != 0 {
            FileHandle.standardError.write(
                Data("rs_set_app_user_model_id failed: HRESULT 0x\(String(aumidStatus, radix: 16))\n".utf8))
        }

        var exeBuf = [UInt16](repeating: 0, count: 1024)
        let written = exeBuf.withUnsafeMutableBufferPointer {
            rs_get_self_exe_path($0.baseAddress, Int32($0.count))
        }
        guard written > 0 else {
            FileHandle.standardError.write(Data("rs_get_self_exe_path failed\n".utf8))
            return
        }
        let exePath = String(decoding: exeBuf[0..<Int(written)], as: UTF16.self)

        let title = App.context.tr("newWindow")
        let registerStatus = rs_register_new_window_task(
            wide(aumid), wide(exePath), wide("--new-window"), wide(title), wide(exePath), 0)
        if registerStatus != 0 {
            FileHandle.standardError.write(
                Data("rs_register_new_window_task failed: HRESULT 0x\(String(registerStatus, radix: 16))\n".utf8))
        }
    }

    override open func onShutdown(exitCode: Int32) {
        // Allow modules to deinit
        App.context.modules = []
    }
}
