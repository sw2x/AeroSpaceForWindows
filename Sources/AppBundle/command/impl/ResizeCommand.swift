import Foundation
import Common

struct ResizeCommand: Command {
    let args: ResizeCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        if let window = target.windowOrNil, window.isFloating {
            guard var size = try? await window.getNativeSize(.nonCancellable) else {
                return .fail(io.err("Cannot read the floating window size"))
            }
            let orientation: Orientation = switch args.dimension.val {
                case .width: .h
                case .height: .v
                case .smart: target.workspace.rootTilingContainer.orientation
                case .smartOpposite: target.workspace.rootTilingContainer.orientation.opposite
            }
            let previous = orientation == .h ? size.width : size.height
            let next: CGFloat = switch args.units.val {
                case .set(let value): CGFloat(value)
                case .add(let value): previous + CGFloat(value)
                case .subtract(let value): previous - CGFloat(value)
            }
            guard next >= 1 else { return .fail(io.err("Window dimensions must be positive")) }
            if orientation == .h { size.width = next } else { size.height = next }
            window.setNativeFrame(nil, size)
            window.lastFloatingSize = size
            return .succ
        }

        let candidates = target.windowOrNil?.parentsWithSelf
            .filter { ($0.parent as? TilingContainer)?.layout == .tiles }
            ?? []

        let orientation: Orientation?
        let parent: TilingContainer?
        let node: TreeNode?
        switch args.dimension.val {
            case .width:
                orientation = .h
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
            case .height:
                orientation = .v
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
            case .smart:
                node = candidates.first
                parent = node?.parent as? TilingContainer
                orientation = parent?.orientation
            case .smartOpposite:
                orientation = (candidates.first?.parent as? TilingContainer)?.orientation.opposite
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
        }
        guard let parent else {
            return .fail(io.err("No tiles container along the requested dimension"))
        }
        guard let orientation else { return .fail }
        guard let node else { return .fail }
        let diff: CGFloat = switch args.units.val {
            case .set(let unit): CGFloat(unit) - node.getWeight(orientation)
            case .add(let unit): CGFloat(unit)
            case .subtract(let unit): -CGFloat(unit)
        }

        guard let childDiff = diff.div(parent.children.count - 1) else { return .fail }
        guard node.getWeight(orientation) + diff > 0,
              parent.children.filter({ $0 != node }).allSatisfy({ $0.getWeight(orientation) - childDiff > 0 }) else {
            return .fail(io.err("Resize would make a tile dimension nonpositive"))
        }
        parent.children.lazy
            .filter { $0 != node }
            .forEach { $0.setWeight(parent.orientation, $0.getWeight(parent.orientation) - childDiff) }

        node.setWeight(orientation, node.getWeight(orientation) + diff)
        return .succ
    }
}
