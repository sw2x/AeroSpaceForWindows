import Foundation
import Common

struct CloseCommand: Command {
    let args: CloseCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else {
            return .fail(io.err("Empty workspace"))
        }
        if args.quitIfLastWindow { return .fail(io.err("--quit-if-last-window is not supported on Windows; use close without that flag")) }
        window.closeNativeWindow()
        return .succ
    }
}
