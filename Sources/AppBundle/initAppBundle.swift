import Foundation
import Common
import NativeWindows

struct ServerArgs: Sendable { var configLocation: String?; var isReadOnly = false; var manageProcess: UInt32? }
nonisolated(unsafe) var serverArgs = ServerArgs()

@MainActor public func initAppBundle(args: [String]) async {
    _isCli = false
    initTerminationHandler()
    var index = 0
    while index < args.count {
        switch args[index] {
            case "--read-only": serverArgs.isReadOnly = true
            case "--config-path":
                index += 1
                guard index < args.count else { aw_shutdown(); Common.exit(2, err: "Missing config path") }
                serverArgs.configLocation = args[index]
            case "--manage-process":
                index += 1
                guard index < args.count, let pid = UInt32(args[index]) else { aw_shutdown(); Common.exit(2, err: "--manage-process requires a numeric PID") }
                serverArgs.manageProcess = pid
            default: aw_shutdown(); Common.exit(2, err: "Unknown option: \(args[index])")
        }
        index += 1
    }
    Thread.detachNewThread {
        aw_run_loop { event, value in
            Task { @MainActor in await handleNativeEvent(event, value) }
        }
    }
    while aw_loop_ready() == 0 { try? await Task.sleep(for: .milliseconds(20)) }
    guard aw_loop_ready() == 1, aw_start_watchdog() != 0 else {
        aw_shutdown(); Common.exit(2, err: "Can't start event loop or recovery watchdog")
    }
    let result = await reloadConfig_nonCancellable()
    guard result.isOk else {
        aw_message("AeroSpace startup configuration error", result.stdout + result.stderr)
        aw_shutdown(); Common.exit(2, err: result.stdout + result.stderr)
    }
    if serverArgs.isReadOnly { TrayMenuModel.shared.isEnabled = false; resetHotKeys() }
    Workspace.garbageCollectUnusedWorkspaces()
    _ = Workspace.all.first?.focusWorkspace()
    await runHeavyCompleteRefreshSession(.startup, assumeCancellable: false)
    startPipeServer()
    if !serverArgs.isReadOnly { _ = await config.afterStartupCommand.run(.defaultEnv, .emptyStdin) }
    while true { try? await Task.sleep(for: .seconds(1)) }
}

@MainActor private func handleNativeEvent(_ event: Int32, _ value: UInt64) async {
    switch event {
        case 1, 2: scheduleCancellableCompleteRefreshSession(.globalObserver("WinEvent"))
        case 3:
            guard let binding = registeredBindings[Int32(value)], TrayMenuModel.shared.isEnabled else { return }
            do {
                try await runLightSession(.hotkeyBinding, .forceRun) { _ = await binding.commands.run(.defaultEnv, .emptyStdin) }
            } catch { eprint("Hotkey failed: \(error)") }
        case 4:
            DesktopWindow.allWindows.forEach { $0.invalidateLayout() }
            scheduleCancellableCompleteRefreshSession(.globalObserver("DisplayChange"))
        case 5:
            let command = EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .toggle))
            do { try await runLightSession(.menuBarButton, .forceRun) { _ = await command.run(.defaultEnv, .emptyStdin) } }
            catch { eprint("\(error)") }
        case 6:
            let result = await reloadConfig_nonCancellable()
            if !result.isOk { aw_message("AeroSpace configuration error", result.stdout + result.stderr) }
        case 7: terminateApp()
        case 8: currentlyManipulatedWithMouseWindowId = DesktopWindow.byHandle[value]?.windowId
        case 9:
            currentlyManipulatedWithMouseWindowId = nil
            DesktopWindow.byHandle[value]?.invalidateLayout()
            scheduleCancellableCompleteRefreshSession(.globalObserver("MoveSizeEnd"))
        default: break
    }
}

var isStartup: Bool { refreshSessionEvent?.isStartup == true }
