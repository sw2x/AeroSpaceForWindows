import Foundation
import Common

struct ReloadConfigCommand: Command {
    let args: ReloadConfigCmdArgs
    let shouldResetClosedWindowsCache = false
    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        let result = await reloadConfig_nonCancellable(args: args)
        if !result.stdout.isEmpty { io.out(result.stdout) }
        if !result.stderr.isEmpty { io.err(result.stderr) }
        return .from(bool: result.isOk)
    }
}
struct ReloadConfigResult { let isOk: Bool; let stdout: String; let stderr: String }
@MainActor func reloadConfig_nonCancellable(args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []), forceConfigUrl: URL? = nil) async -> ReloadConfigResult {
    let result = readConfig(forceConfigUrl: forceConfigUrl)
    let parsed = result.parseConfigResult
    var errors = parsed.errors.map { $0.description(.error) }
    let warnings = parsed.warnings.map { $0.description(.warning) }
    if args.warningsAsErrors { errors += warnings }
    if errors.isEmpty, !args.dryRun {
        let targetMode = activeMode.flatMap { parsed.config.modes[$0] != nil ? $0 : nil } ?? mainModeId
        let bindings = TrayMenuModel.shared.isEnabled && !serverArgs.isReadOnly ? (parsed.config.modes[targetMode]?.bindings ?? [:]) : [:]
        if let error = replaceHotkeys(bindings) { errors.append(error) }
        else {
            config = parsed.config
            configUrl = result.configUrl
            activeMode = targetMode
            DesktopWindow.allWindows.forEach { $0.invalidateLayout() }
            syncConfigFileWatcher()
        }
    }
    return ReloadConfigResult(isOk: errors.isEmpty, stdout: errors.joined(separator: "\n"), stderr: args.warningsAsErrors ? "" : warnings.joined(separator: "\n"))
}
