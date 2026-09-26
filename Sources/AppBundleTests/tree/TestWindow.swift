@testable import AppBundle
import Foundation

final class TestWindow: Window, CustomStringConvertible {
    private var _rect: Rect?
    var isNativeFullscreenForTest = false

    @MainActor
    private init(_ id: UInt32, _ parent: NonLeafTreeNodeObject, _ adaptiveWeight: CGFloat, _ rect: Rect?) {
        _rect = rect
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: parent, adaptiveWeight: adaptiveWeight, index: INDEX_BIND_LAST)
    }

    @discardableResult
    @MainActor
    static func new(id: UInt32, parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat = 1, rect: Rect? = nil) -> TestWindow {
        let wi = TestWindow(id, parent, adaptiveWeight, rect)
        TestApp.shared._windows.append(wi)
        return wi
    }

    nonisolated var description: String { "TestWindow(\(windowId))" }

    @MainActor
    override func nativeFocus() {
        appForTests = TestApp.shared
        TestApp.shared.focusedWindow = self
    }

    override func closeNativeWindow() {
        unbindFromParent()
    }

    override func getTitle(_ cm: CancellationMode) async throws -> String { description }

    @MainActor override func getNativeRect(_ cm: CancellationMode) async throws -> Rect? { // todo change to not Optional
        _rect
    }

    @MainActor override func getNativeSize(_ cm: CancellationMode) async throws -> CGSize? {
        _rect.map { CGSize(width: $0.width, height: $0.height) }
    }

    override func setNativeFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        let point = topLeft ?? _rect?.topLeftCorner ?? .zero
        let dimensions = size ?? _rect?.size ?? .zero
        _rect = Rect(topLeftX: point.x, topLeftY: point.y, width: dimensions.width, height: dimensions.height)
    }

    override func isNativeFullscreen(_ cm: CancellationMode) async throws -> Bool { isNativeFullscreenForTest }
}
