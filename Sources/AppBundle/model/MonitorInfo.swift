import Foundation
import Common
import NativeWindows

protocol MonitorInfo: AeroAny {
    var nativeMonitorIndex: Int { get }
    var name: String { get }
    var rect: Rect { get }
    var visibleRect: Rect { get }
    var width: CGFloat { get }
    var height: CGFloat { get }
    var isMain: Bool { get }
}
struct DesktopMonitor: MonitorInfo {
    let nativeMonitorIndex: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool
    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
}
private let fallbackMonitor = DesktopMonitor(nativeMonitorIndex: 1, name: "Test Monitor",
    rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
    visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080), isMain: true)
nonisolated(unsafe) var monitorsForTests: [any MonitorInfo]? = nil
var monitorInfos: [any MonitorInfo] {
    if isUnitTest { return monitorsForTests ?? [fallbackMonitor] }
    var count: Int32 = 0
    guard let values = aw_monitors(&count) else { return [fallbackMonitor] }
    defer { aw_free(values) }
    let result: [any MonitorInfo] = (0..<Int(count)).map { index in
        let value = values[index]
        return DesktopMonitor(nativeMonitorIndex: index + 1, name: nativeString(value.name),
                              rect: value.rect.model, visibleRect: value.work.model, isMain: value.primary != 0)
    }
    return result.isEmpty ? [fallbackMonitor] : result
}
var mainMonitorInfo: any MonitorInfo { monitorInfos.first(where: \.isMain) ?? monitorInfos[0] }
var sortedMonitorInfos: [any MonitorInfo] { monitorInfos.sortedBy([\.rect.minX, \.rect.minY]) }
