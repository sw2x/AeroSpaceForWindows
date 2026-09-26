import Foundation
import Common

struct ExecAndForgetCommand: Command {
    let args: ExecAndForgetCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        // todo shall exec-and-forget fork exec session?
        // It doesn't throw if exit code is non-zero
        return .from(bool: launchPowerShell(args.bashScript, environment: config.execConfig.envVariables + env.asMap))
    }
}
