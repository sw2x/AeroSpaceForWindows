import Foundation
import Common
import NativeWindows

@MainActor final class TrayMenuModel {
    static let shared = TrayMenuModel()
    var isEnabled = true
    var lastReloadConfigContainedWarnings = false
}
@MainActor func updateTrayText() {
    let enabled = TrayMenuModel.shared.isEnabled
    let workspaceName = enabled ? focus.workspace.name : ""
    aw_tray_text(enabled ? "AeroSpace — \(workspaceName)" : "AeroSpace — disabled",
                 workspaceName, enabled ? 1 : 0)
}
// Event subscriptions are reserved for a later release; callbacks still run locally.
@MainActor func broadcastEvent(_ event: ServerEvent) {}
