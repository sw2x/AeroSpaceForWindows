import Common

enum TreeNodeCases {
    case window(Window)
    case tilingContainer(TilingContainer)
    case workspace(Workspace)
    case nativeMinimizedWindowsContainer(NativeMinimizedWindowsContainer)
    case nativeHiddenWindowsContainer(NativeHiddenWindowsContainer)
    case nativeFullscreenWindowsContainer(NativeFullscreenWindowsContainer)
    case nativePopupWindowsContainer(NativePopupWindowsContainer)
    case floatingWindowsContainer(FloatingWindowsContainer)
}

enum NonLeafTreeNodeCases {
    case tilingContainer(TilingContainer)
    case workspace(Workspace)
    case nativeMinimizedWindowsContainer(NativeMinimizedWindowsContainer)
    case nativeHiddenWindowsContainer(NativeHiddenWindowsContainer)
    case nativeFullscreenWindowsContainer(NativeFullscreenWindowsContainer)
    case nativePopupWindowsContainer(NativePopupWindowsContainer)
    case floatingWindowsContainer(FloatingWindowsContainer)
}

enum TilingTreeNodeCases {
    case window(Window)
    case tilingContainer(TilingContainer)
}

enum NonLeafTreeNodeKind: Equatable {
    case tilingContainer
    case workspace
    case nativeMinimizedWindowsContainer
    case nativeHiddenWindowsContainer
    case nativeFullscreenWindowsContainer
    case nativePopupWindowsContainer
    case floatingWindowsContainer
}

enum WindowParentCases {
    case unbound
    case tilingContainer(TilingContainer)
    case nativeMinimizedWindowsContainer(NativeMinimizedWindowsContainer)
    case nativeHiddenWindowsContainer(NativeHiddenWindowsContainer)
    case nativeFullscreenWindowsContainer(NativeFullscreenWindowsContainer)
    case nativePopupWindowsContainer(NativePopupWindowsContainer)
    case floatingWindowsContainer(FloatingWindowsContainer)
}

enum TilingContainerParentCases {
    case unbound
    case tilingContainer(TilingContainer)
    case workspace(Workspace)
}

enum ConventionalWindowParentCases {
    case tilingContainer(TilingContainer)
    case floatingWindowsContainer(FloatingWindowsContainer)

    var tilingContainerOrNil: TilingContainer? {
        switch self {
            case .tilingContainer(let it): it
            default: nil
        }
    }

    var floatingWindowsContainerOrNil: FloatingWindowsContainer? {
        switch self {
            case .floatingWindowsContainer(let it): it
            default: nil
        }
    }
}

protocol NonLeafTreeNodeObject: TreeNode {}

extension Window {
    var windowParentCases: WindowParentCases {
        guard let parent else { return .unbound }
        return switch parent.cases {
            case .floatingWindowsContainer(let it): .floatingWindowsContainer(it)
            case .nativeFullscreenWindowsContainer(let it): .nativeFullscreenWindowsContainer(it)
            case .nativeHiddenWindowsContainer(let it): .nativeHiddenWindowsContainer(it)
            case .nativeMinimizedWindowsContainer(let it): .nativeMinimizedWindowsContainer(it)
            case .nativePopupWindowsContainer(let it): .nativePopupWindowsContainer(it)
            case .tilingContainer(let it): .tilingContainer(it)
            case .workspace: dieT("Workspace can't have direct Window children")
        }
    }
}

extension TilingContainer {
    var tilingContainerParentCases: TilingContainerParentCases {
        guard let parent else { return .unbound }
        return switch parent.cases {
            case .tilingContainer(let it): .tilingContainer(it)
            case .workspace(let it): .workspace(it)
            case .floatingWindowsContainer: dieT("floatingWindowsContainer can't be TilingContainer's parent")
            case .nativeFullscreenWindowsContainer: dieT("nativeFullscreenWindowsContainer can't be TilingContainer's parent")
            case .nativeHiddenWindowsContainer: dieT("nativeHiddenWindowsContainer can't be TilingContainer's parent")
            case .nativeMinimizedWindowsContainer: dieT("nativeMinimizedWindowsContainer can't be TilingContainer's parent")
            case .nativePopupWindowsContainer: dieT("nativePopupWindowsContainer can't be TilingContainer's parent")
        }
    }
}

extension TreeNode {
    var nodeCases: TreeNodeCases {
        switch self {
            case let window as Window: .window(window)
            case let workspace as Workspace: .workspace(workspace)
            case let tilingContainer as TilingContainer: .tilingContainer(tilingContainer)
            case let container as NativeHiddenWindowsContainer: .nativeHiddenWindowsContainer(container)
            case let container as NativeMinimizedWindowsContainer: .nativeMinimizedWindowsContainer(container)
            case let container as NativeFullscreenWindowsContainer: .nativeFullscreenWindowsContainer(container)
            case let container as NativePopupWindowsContainer: .nativePopupWindowsContainer(container)
            case let container as FloatingWindowsContainer: .floatingWindowsContainer(container)
            default: die("Unknown tree")
        }
    }

    func tilingTreeNodeCasesOrDie() -> TilingTreeNodeCases {
        switch self {
            case let window as Window: .window(window)
            case let tilingContainer as TilingContainer: .tilingContainer(tilingContainer)
            default: illegalChildParentRelation(child: self, parent: parent)
        }
    }
}

extension NonLeafTreeNodeObject {
    var cases: NonLeafTreeNodeCases {
        switch self {
            case is Window: die("Windows are leaf nodes. They can't have children")
            case let workspace as Workspace: .workspace(workspace)
            case let tilingContainer as TilingContainer: .tilingContainer(tilingContainer)
            case let container as NativeMinimizedWindowsContainer: .nativeMinimizedWindowsContainer(container)
            case let container as NativeHiddenWindowsContainer: .nativeHiddenWindowsContainer(container)
            case let container as NativeFullscreenWindowsContainer: .nativeFullscreenWindowsContainer(container)
            case let container as NativePopupWindowsContainer: .nativePopupWindowsContainer(container)
            case let container as FloatingWindowsContainer: .floatingWindowsContainer(container)
            default: die("Unknown tree \(self)")
        }
    }

    var kind: NonLeafTreeNodeKind {
        switch cases {
            case .tilingContainer: .tilingContainer
            case .floatingWindowsContainer: .floatingWindowsContainer
            case .workspace: .workspace
            case .nativeMinimizedWindowsContainer: .nativeMinimizedWindowsContainer
            case .nativeFullscreenWindowsContainer: .nativeFullscreenWindowsContainer
            case .nativeHiddenWindowsContainer: .nativeHiddenWindowsContainer
            case .nativePopupWindowsContainer: .nativePopupWindowsContainer
        }
    }
}

enum ChildParentRelation: Equatable {
    case floatingWindow
    case nativeFullscreenWindow
    case nativeHiddenWindow
    case nativeMinimizedWindow
    case nativePopupWindow
    case tiling(parent: TilingContainer) // todo consider splitting it on 'tiles' and 'accordion'
    case rootTilingContainer

    case shimContainerRelation
}

func getChildParentRelation(child: TreeNode, parent: NonLeafTreeNodeObject) -> ChildParentRelation {
    if let relation = getChildParentRelationOrNil(child: child, parent: parent) {
        return relation
    }
    illegalChildParentRelation(child: child, parent: parent)
}

func illegalChildParentRelation(
    child: TreeNode,
    parent: NonLeafTreeNodeObject?,
    file: StaticString = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> Never {
    let msg = "Illegal child-parent relation. Child: \(child), Parent: \((parent ?? child.parent).prettyDescription)"
    die(msg, file: file, line: line, column: column, function: function)
}

func getChildParentRelationOrNil(child: TreeNode, parent: NonLeafTreeNodeObject) -> ChildParentRelation? {
    return switch (child.nodeCases, parent.cases) {
        case (.workspace, _): nil
        case (.window, .workspace): nil

        case (.window, .nativePopupWindowsContainer): .nativePopupWindow
        case (_, .nativePopupWindowsContainer): nil
        case (.nativePopupWindowsContainer, _): nil

        case (.window, .nativeMinimizedWindowsContainer): .nativeMinimizedWindow
        case (_, .nativeMinimizedWindowsContainer): nil
        case (.nativeMinimizedWindowsContainer, _): nil

        case (.tilingContainer, .tilingContainer(let container)),
             (.window, .tilingContainer(let container)): .tiling(parent: container)
        case (.tilingContainer, .workspace): .rootTilingContainer

        case (.floatingWindowsContainer, .workspace): .shimContainerRelation
        case (.window, .floatingWindowsContainer): .floatingWindow
        case (.floatingWindowsContainer, _): nil
        case (_, .floatingWindowsContainer): nil

        case (.nativeFullscreenWindowsContainer, .workspace): .shimContainerRelation
        case (.window, .nativeFullscreenWindowsContainer): .nativeFullscreenWindow
        case (.nativeFullscreenWindowsContainer, _): nil
        case (_, .nativeFullscreenWindowsContainer): nil

        case (.nativeHiddenWindowsContainer, .workspace): .shimContainerRelation
        case (.window, .nativeHiddenWindowsContainer): .nativeHiddenWindow
        case (.nativeHiddenWindowsContainer, _): nil
        case (_, .nativeHiddenWindowsContainer): nil
    }
}
