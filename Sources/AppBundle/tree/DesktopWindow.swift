import Foundation
import Common
import NativeWindows

final class DesktopWindow: Window {
    let handle: UInt64
    let processCreation: UInt64
    let desktopApp: DesktopApp
    private var lastRequestedRect: Rect?
    @MainActor static var allWindowsMap: [UInt32: DesktopWindow] = [:]
    @MainActor static var byHandle: [UInt64: DesktopWindow] = [:]
    @MainActor static var allWindows: [DesktopWindow] { Array(allWindowsMap.values) }
    @MainActor private static var nextId: UInt32 = 1
    var minimizedWorkspace: Workspace?
    var minimizedBinding: BindingData?

    @MainActor private init(_ info: AWWindow, _ app: DesktopApp, _ workspace: Workspace) {
        handle = info.handle
        processCreation = info.processCreation
        desktopApp = app
        let id = Self.nextId
        Self.nextId += 1
        super.init(id: id, app, lastFloatingSize: info.rect.model.size,
                   parent: info.dialog != 0 || info.resizable == 0 ? workspace.floatingWindowsContainer : workspace.rootTilingContainer,
                   adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }

    @MainActor static func register(_ info: AWWindow) async -> DesktopWindow {
        if let window = byHandle[info.handle], window.processCreation == info.processCreation, window.app.pid == Int32(bitPattern: info.pid) { return window }
        byHandle[info.handle]?.garbageCollect(skipClosedWindowsCache: true)
        let pid = Int32(bitPattern: info.pid)
        let app: DesktopApp
        if let existing = DesktopApp.allAppsMap[pid], existing.creation == info.processCreation { app = existing }
        else { app = DesktopApp(info); DesktopApp.allAppsMap[pid] = app }
        let workspace = isStartup ? info.rect.model.center.monitorApproximation.activeWorkspace : focus.workspace
        let window = DesktopWindow(info, app, workspace)
        byHandle[info.handle] = window
        allWindowsMap[window.windowId] = window
        await tryOnWindowDetected(window)
        return window
    }

    @MainActor func garbageCollect(skipClosedWindowsCache: Bool) {
        if !skipClosedWindowsCache { cacheClosedWindowIfNeeded() }
        Self.allWindowsMap.removeValue(forKey: windowId)
        Self.byHandle.removeValue(forKey: handle)
        _ = unbindFromParent()
    }

    private var info: AWWindow? {
        var value = AWWindow()
        guard aw_window(handle, &value) != 0, value.processCreation == processCreation,
              Int32(bitPattern: value.pid) == app.pid else { return nil }
        return value
    }
    override func getTitle(_ cm: CancellationMode) async throws -> String { try checkCancellation(cm); return info.map { nativeString($0.title) } ?? "" }
    override func getNativeRect(_ cm: CancellationMode) async throws -> Rect? { try checkCancellation(cm); return info?.rect.model }
    override func getNativeSize(_ cm: CancellationMode) async throws -> CGSize? { try await getNativeRect(cm)?.size }
    override func isNativeMinimized(_ cm: CancellationMode) async throws -> Bool { try checkCancellation(cm); return info.map { $0.minimized != 0 } ?? false }
    override func isNativeFullscreen(_ cm: CancellationMode) async throws -> Bool { try checkCancellation(cm); return info != nil && aw_is_fullscreen(handle) != 0 }
    override var isHiddenInCorner: Bool { aw_is_hidden(handle) != 0 }
    @MainActor override func nativeFocus() { _ = requestNativeFocus() }
    @MainActor override func requestNativeFocus() -> Bool { !serverArgs.isReadOnly && info != nil && aw_focus(handle) != 0 }
    @MainActor override func closeNativeWindow() { if !serverArgs.isReadOnly && info != nil { _ = aw_close(handle) } }

    @MainActor override func setNativeFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        guard !serverArgs.isReadOnly, currentlyManipulatedWithMouseWindowId != windowId,
              let info, info.minimized == 0 else { return }
        let current = info.rect.model
        let requested = Rect(topLeftX: topLeft?.x ?? current.topLeftX, topLeftY: topLeft?.y ?? current.topLeftY,
                             width: size?.width ?? current.width, height: size?.height ?? current.height)
        // Minimum-size constraints are allowed: repeated identical layouts do not fight the app.
        if let previous = lastRequestedRect, previous.native.x == requested.native.x,
           previous.native.y == requested.native.y, previous.native.width == requested.native.width,
           previous.native.height == requested.native.height { return }
        if aw_position(handle, requested.native) != 0 { lastRequestedRect = requested }
    }
    func invalidateLayout() { lastRequestedRect = nil }
    @MainActor func setWorkspaceVisible(_ visible: Bool) throws {
        guard !serverArgs.isReadOnly, info != nil else { return }
        if visible {
            guard aw_show(handle) != 0 else { throw PlatformError("Failed to show window \(windowId)") }
        } else if info?.minimized == 0 && !isHiddenInCorner {
            guard aw_hide(handle) != 0 else {
                let error = aw_last_error()
                let reason = error == 5
                    ? "Windows denied access to \(desktopApp.name ?? "this app") (error 5). Run the app without administrator privileges or run AeroSpace at the same integrity level."
                    : "Windows error \(error)."
                throw PlatformError("Failed to hide window \(windowId): \(reason) Workspace change aborted")
            }
        }
    }
}

extension Window {
    @MainActor func relayoutWindow(on workspace: Workspace, _ cm: CancellationMode, forceTile: Bool = false) async throws {
        try checkCancellation(cm)
        if forceTile { bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST) }
        else if isFloating { bindAsFloatingWindow(to: workspace) }
        else { bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST) }
    }
}

struct PlatformError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor
func tryOnWindowDetected(_ window: Window) async {
    switch window.windowParentCases {
        case .tilingContainer, .floatingWindowsContainer, .nativeMinimizedWindowsContainer,
             .nativeFullscreenWindowsContainer, .nativeHiddenWindowsContainer:
            _ = await onWindowDetected(.defaultEnv, CmdIoImpl.emptyStdinIgnoringOut, window)
        case .nativePopupWindowsContainer, .unbound:
            break
    }
}

@MainActor
func onWindowDetected(_ env: CmdEnv, _ io: CmdIo, _ window: Window) async -> Int32ExitCode {
    broadcastEvent(.windowDetected(
        windowId: window.windowId,
        workspace: window.nodeWorkspace?.name,
        appId: window.app.rawAppId,
        appName: window.app.name,
    ))
    var lastExitCode = Int32ExitCode.succ
    for callback in config.onWindowDetected where await callback.matches(window) {
        lastExitCode = await callback.run.run(env.withWindowId(window.windowId), io)
        if !callback.checkFurtherCallbacks {
            return lastExitCode
        }
    }
    return lastExitCode
}

extension WindowDetectedCallback {
    @MainActor
    func matches(_ window: Window) async -> Bool {
        switch self.matcher {
            case .legacy(let matcher):
                if let startupMatcher = matcher.duringAeroSpaceStartup, startupMatcher != isStartup {
                    return false
                }
                if let regex = matcher.windowTitleRegexSubstring, (try? await window.getTitle(.nonCancellable))?.contains(caseInsensitiveRegex: regex) != true {
                    return false
                }
                if let appId = matcher.appId, appId != window.app.rawAppId {
                    return false
                }
                if let regex = matcher.appNameRegexSubstring, !(window.app.name ?? "").contains(caseInsensitiveRegex: regex) {
                    return false
                }
                if let workspace = matcher.workspace, workspace != window.nodeWorkspace?.name {
                    return false
                }
                return true
            case .command(let command):
                return await command.run(.defaultEnv.withWindowId(window.windowId), .emptyStdin).exitCode.rawValue == 0
        }
    }
}
