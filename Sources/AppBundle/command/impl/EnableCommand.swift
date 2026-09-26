import Foundation
import Common

struct EnableCommand: Command {
    let args: EnableCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard !serverArgs.isReadOnly else { return .fail(io.err("AeroSpace was started with --read-only")) }
        let prevState = TrayMenuModel.shared.isEnabled
        let newState: Bool = switch args.targetState.val {
            case .on: true
            case .off: false
            case .toggle: !TrayMenuModel.shared.isEnabled
        }
        if newState == prevState {
            switch args.failIfNoop {
                case true: return .fail
                case false:
                    let msg = newState
                        ? "Already enabled. Tip: use --fail-if-noop to exit with non-zero code"
                        : "Already disabled. Tip: use --fail-if-noop to exit with non-zero code"
                    return .succ(io.err(msg))
            }
        }

        TrayMenuModel.shared.isEnabled = newState
        if newState {
            for workspace in Workspace.all {
                for window in workspace.allLeafWindowsRecursive where window.isFloating {
                    window.lastFloatingSize = (try? await window.getNativeSize(.nonCancellable)) ?? window.lastFloatingSize
                }
            }
            if !(await activateMode_nonCancellable(mainModeId)) {
                TrayMenuModel.shared.isEnabled = false
                return .fail(io.err("Cannot enable AeroSpace because a hotkey is unavailable"))
            }
        } else {
            await activateMode_nonCancellable(nil)
        }
        return .succ
    }
}
