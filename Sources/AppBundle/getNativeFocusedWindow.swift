import Common
import NativeWindows

@MainActor var appForTests: (any AbstractApp)? = nil
@MainActor func getNativeFocusedWindow(_ cm: CancellationMode) async throws -> Window? {
    try checkCancellation(cm)
    if isUnitTest { return try await appForTests?.getFocusedWindow(cm) }
    return DesktopWindow.byHandle[aw_foreground()]
}
