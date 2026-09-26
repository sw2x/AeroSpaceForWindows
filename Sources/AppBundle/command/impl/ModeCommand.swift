import Foundation
import Common

struct ModeCommand: Command {
    let args: ModeCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        return await activateMode_nonCancellable(args.targetMode.val) ? .succ : .fail(io.err("Unable to activate mode: missing mode or hotkey conflict"))
    }
}
