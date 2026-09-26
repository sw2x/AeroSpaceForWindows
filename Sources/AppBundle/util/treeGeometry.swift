import Foundation
import Common
import NativeWindows

var mouseLocation: CGPoint { let point = aw_cursor(); return CGPoint(x: Double(point.x), y: Double(point.y)) }
@MainActor func swapWindows(mruDominant window1: Window, _ window2: Window) {
    if window1 == window2 { return }
    let binding2 = window2.unbindFromParent()
    let binding1 = window1.unbindFromParent()
    window2.bind(to: binding1.parent, adaptiveWeight: binding1.adaptiveWeight, index: binding1.index)
    window1.bind(to: binding2.parent, adaptiveWeight: binding2.adaptiveWeight, index: binding2.index)
    window1.markAsMostRecentChild()
}
extension CGPoint {
    @MainActor func findWindowRecursively(in tree: TilingContainer, virtual: Bool, fullscreenCoversAll: Bool) -> Window? {
        if fullscreenCoversAll, let window = tree.mostRecentWindowRecursive, window.isFullscreen { return window }
        let target: TreeNode?
        switch tree.layout {
            case .tiles: target = tree.children.first { (virtual ? $0.lastAppliedLayoutVirtualRect : $0.lastAppliedLayoutPhysicalRect)?.contains(self) == true }
            case .accordion: target = tree.mostRecentChild
        }
        switch target {
            case let window as Window: return window
            case let container as TilingContainer: return findWindowRecursively(in: container, virtual: virtual, fullscreenCoversAll: fullscreenCoversAll)
            default: return nil
        }
    }
}
