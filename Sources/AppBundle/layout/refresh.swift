import Foundation
import Common
import NativeWindows

@MainActor private var refreshTask: Task<Void, Never>?
@MainActor private var refreshInProgress = false
@MainActor private var pendingRefresh = false
@MainActor private var sessionBusy = false
@MainActor private var sessionWaiters: [CheckedContinuation<Void, Never>] = []
@MainActor private func acquireSession() async {
    if !sessionBusy { sessionBusy = true; return }
    await withCheckedContinuation { sessionWaiters.append($0) }
}
@MainActor private func releaseSession() {
    if sessionWaiters.isEmpty { sessionBusy = false }
    else { sessionWaiters.removeFirst().resume() }
}
@MainActor var currentlyManipulatedWithMouseWindowId: UInt32?

@MainActor final class NativeFocusIntent {
    var requested = false
    var isActive = true
}

@TaskLocal var nativeFocusIntent: NativeFocusIntent? = nil

@MainActor func recordNativeFocusIntent(_ command: any Command, exitCode: Int32) {
    guard exitCode == EXIT_CODE_ZERO, let intent = nativeFocusIntent, intent.isActive else { return }
    switch command.info.kind {
        case .focus, .focusBackAndForth, .focusMonitor, .workspace,
             .workspaceBackAndForth, .summonWorkspace:
            intent.requested = true
        default: break
    }
}

@MainActor func scheduleCancellableCompleteRefreshSession(_ event: RefreshSessionEvent, optimisticallyPreLayoutWorkspaces: Bool = false) {
    if refreshTask != nil { pendingRefresh = true; return }
    refreshTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(150))
        repeat {
            pendingRefresh = false
            await runHeavyCompleteRefreshSession(event, assumeCancellable: false)
        } while pendingRefresh
        refreshTask = nil
    }
}

@MainActor func runHeavyCompleteRefreshSession(_ event: RefreshSessionEvent, assumeCancellable: Bool,
    layoutWorkspaces shouldLayout: Bool = true, optimisticallyPreLayoutWorkspaces: Bool = false) async {
    guard !refreshInProgress else { return }
    refreshInProgress = true
    defer { refreshInProgress = false }
    await acquireSession()
    defer { releaseSession() }
    do {
        try await $refreshSessionEvent.withValue(event) {
            await discoverWindows()
            gcMonitors()
            try await normalizeLayoutReason()
            updateFocusCache(try await getNativeFocusedWindow(.cancellable))
            await refreshModel_nonCancellable()
            if shouldLayout { try await layoutWorkspaces() }
            updateTrayText()
        }
    } catch {
        aw_restore_all()
        eprint("Window refresh failed: \(error)")
    }
}

@MainActor private func discoverWindows() async {
    if isUnitTest { return }
    var count: Int32 = 0
    guard let native = aw_windows(&count) else { return }
    defer { aw_free(native) }
    let selected = (0..<Int(count)).filter { serverArgs.manageProcess == nil || native[$0].pid == serverArgs.manageProcess }
    let handles = Set(selected.map { native[$0].handle })
    for window in DesktopWindow.allWindows where !handles.contains(window.handle) {
        window.garbageCollect(skipClosedWindowsCache: false)
    }
    for index in selected { _ = await DesktopWindow.register(native[index]) }
    let pids = Set(DesktopWindow.allWindows.map { $0.app.pid })
    DesktopApp.allAppsMap = DesktopApp.allAppsMap.filter { pids.contains($0.key) }
}

@MainActor func runLightSession<T>(_ event: RefreshSessionEvent, _: RunSessionGuard,
    body: @MainActor () async throws -> T) async throws -> T {
    await acquireSession()
    defer { releaseSession() }
    let intent = NativeFocusIntent()
    // Child tasks inherit task-local values. Seal this object when the session
    // ends so a later debounced refresh cannot affect a completed request.
    defer { intent.isActive = false }
    return try await $nativeFocusIntent.withValue(intent) {
        try await $refreshSessionEvent.withValue(event) {
            let previous = focus
            do {
                let result = try await body()
                await refreshModel_nonCancellable()
                try await layoutWorkspaces()
                if !serverArgs.isReadOnly, TrayMenuModel.shared.isEnabled,
                   intent.requested || previous != focus,
                   let window = focus.windowOrNil, !window.requestNativeFocus() {
                    throw PlatformError("Windows denied foreground activation of window \(window.windowId)")
                }
                updateTrayText()
                return result
            } catch {
                _ = setFocus(to: previous)
                try? await layoutWorkspaces()
                throw error
            }
        }
    }
}

@MainActor func refreshModel_nonCancellable() async {
    Workspace.garbageCollectUnusedWorkspaces()
    for workspace in Workspace.all { workspace.normalizeContainers() }
    await checkOnFocusChangedCallbacks_nonCancellable()
}

@MainActor func layoutWorkspaces() async throws {
    if isUnitTest { return }
    if !TrayMenuModel.shared.isEnabled || serverArgs.isReadOnly { aw_restore_all(); return }
    for monitor in monitorInfos {
        let workspace = monitor.activeWorkspace
        for window in workspace.allLeafWindowsRecursive { try (window as? DesktopWindow)?.setWorkspaceVisible(true) }
        try await workspace.layoutWorkspace()
    }
    for workspace in Workspace.all where !workspace.isVisible {
        for window in workspace.allLeafWindowsRecursive { try (window as? DesktopWindow)?.setWorkspaceVisible(false) }
    }
}

struct RunSessionGuard: Sendable {
    static let forceRun = RunSessionGuard()
    @MainActor static var isServerEnabled: RunSessionGuard? { TrayMenuModel.shared.isEnabled ? forceRun : nil }
    @MainActor static func isServerEnabled(orIsEnableCommand command: (any Command)?) -> RunSessionGuard? {
        guard let command else { return .isServerEnabled }
        switch command.info.kind {
            case .config, .echo, .listApps, .listExecEnvVars, .listModes, .listMonitors,
                 .listWindows, .listWorkspaces, .test, .testNot, ._true, ._false, .reloadConfig:
                return .forceRun
            case .enable: return serverArgs.isReadOnly ? nil : .forceRun
            default: return .isServerEnabled
        }
    }
    @MainActor static func checkServerIsEnabledOrDie(file: StaticString = #fileID, line: Int = #line,
        column: Int = #column, function: String = #function) -> RunSessionGuard {
        isServerEnabled ?? dieT("Server is disabled", file: file, line: line, column: column, function: function)
    }
}
