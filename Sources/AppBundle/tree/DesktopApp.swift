import Foundation
import Common
import NativeWindows

final class DesktopApp: AbstractApp {
    let pid: Int32
    let creation: UInt64
    let rawAppId: String?
    let name: String?
    let execPath: String?
    var executableDirectory: String? { execPath.map { URL(filePath: $0).deletingLastPathComponent().path } }
    @MainActor static var allAppsMap: [Int32: DesktopApp] = [:]

    init(_ info: AWWindow) {
        pid = Int32(bitPattern: info.pid)
        creation = info.processCreation
        name = nativeString(info.name)
        rawAppId = name?.lowercased()
        execPath = nativeString(info.executable)
    }

    @MainActor func getFocusedWindow(_ cm: CancellationMode) async throws -> Window? {
        try checkCancellation(cm)
        guard let window = DesktopWindow.byHandle[aw_foreground()], window.app.pid == pid else { return nil }
        return window
    }
}

func nativeString<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { bytes in
        String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
}

extension AWRect {
    var model: Rect { Rect(topLeftX: Double(x), topLeftY: Double(y), width: Double(width), height: Double(height)) }
}

extension Rect {
    var native: AWRect {
        AWRect(x: Int32(clamping: Int(topLeftX.rounded())), y: Int32(clamping: Int(topLeftY.rounded())),
               width: Int32(clamping: Int(width.rounded())), height: Int32(clamping: Int(height.rounded())))
    }
}
