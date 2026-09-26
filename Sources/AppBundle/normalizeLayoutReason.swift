import Common

@MainActor func normalizeLayoutReason() async throws {
    for window in DesktopWindow.allWindows {
        let minimized = try await window.isNativeMinimized(.cancellable)
        let fullscreen = try await window.isNativeFullscreen(.cancellable)
        let isNative = window.parent is NativeMinimizedWindowsContainer || window.parent is NativeFullscreenWindowsContainer
        if minimized || fullscreen {
            if !isNative {
                window.minimizedWorkspace = window.nodeWorkspace
                window.minimizedBinding = window.unbindFromParent()
            }
            if minimized, !(window.parent is NativeMinimizedWindowsContainer) {
                window.bind(to: nativeMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
            } else if !minimized, !(window.parent is NativeFullscreenWindowsContainer) {
                window.bind(to: (window.minimizedWorkspace ?? focus.workspace).nativeFullscreenWindowsContainer,
                            adaptiveWeight: 1, index: INDEX_BIND_LAST)
            }
        } else if isNative {
            let workspace = window.minimizedWorkspace ?? focus.workspace
            if let binding = window.minimizedBinding,
               binding.parent.nodeWorkspace == workspace {
                window.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight,
                            index: min(binding.index, binding.parent.children.count))
            } else {
                window.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            }
            window.minimizedBinding = nil
            window.minimizedWorkspace = nil
            window.invalidateLayout()
        }
    }
}
