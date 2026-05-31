import Foundation
import RsHelper
import CRsUIJumpList

// Taskbar right-click "New Window" entry. Backed by Win32 COM
// (ICustomDestinationList via the CRsUIJumpList bridge) because an unpackaged
// EXE can't use the WinRT JumpList API. Keeping the C marshaling here means a
// future switch to WinRT JumpList only touches this file, not App.swift.
enum TaskbarJumpList {
    // Sets the process AUMID and registers one task that relaunches this EXE.
    // Failures are logged, never thrown — a missing taskbar entry must not
    // block startup.
    static func registerNewWindow(aumid: String, title: String, argument: String = "--new-window") {
        let aumidStatus = rs_set_app_user_model_id(wide(aumid))
        if aumidStatus != 0 {
            log.warning("rs_set_app_user_model_id failed: HRESULT 0x\(String(aumidStatus, radix: 16))")
        }

        guard let exePath = selfExePath() else {
            log.warning("rs_get_self_exe_path failed")
            return
        }

        let status = rs_register_new_window_task(
            wide(aumid), wide(exePath), wide(argument), wide(title), wide(exePath), 0)
        if status != 0 {
            log.warning("rs_register_new_window_task failed: HRESULT 0x\(String(status, radix: 16))")
        }
    }

    private static func selfExePath() -> String? {
        var buf = [UInt16](repeating: 0, count: 1024)
        let written = buf.withUnsafeMutableBufferPointer {
            rs_get_self_exe_path($0.baseAddress, Int32($0.count))
        }
        guard written > 0 else { return nil }
        return String(decoding: buf[0..<Int(written)], as: UTF16.self)
    }

    // Null-terminated wide-char array passed straight as const wchar_t* to the
    // C bridge, avoiding per-argument nested withCString.
    private static func wide(_ s: String) -> [UInt16] { Array(s.utf16) + [0] }
}
