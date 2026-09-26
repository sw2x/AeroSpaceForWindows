import Foundation
import Common
import NativeWindows

@MainActor final class TrayMenuModel {
    static let shared = TrayMenuModel()
    var isEnabled = true
    var lastReloadConfigContainedWarnings = false
}
@MainActor func updateTrayText() {
    aw_tray_text(TrayMenuModel.shared.isEnabled ? "AeroSpace — \(focus.workspace.name)" : "AeroSpace — disabled", TrayMenuModel.shared.isEnabled ? 1 : 0)
}
// Event subscriptions are reserved for a later release; callbacks still run locally.
@MainActor func broadcastEvent(_ event: ServerEvent) {}
