import Foundation

enum RightUtilityPresentation: Equatable {
    case hidden
    case railOnly(width: Double)
    case expanded(width: Double)
}

struct ShellWidthAllocation: Equatable {
    let leftWidth: Double?
    let centerWidth: Double
    let right: RightUtilityPresentation
}

enum ShellWidthAllocator {
    static let supportedMinimumContentWidth = 570.0
    static let reservedCenterWidth = 320.0
    static let minimumLeftWidth = 220.0
    static let minimumRightWidth = 250.0
    static let rightRailWidth = 40.0

    static func allocate(
        containerWidth: Double,
        requestedLeftWidth: Double,
        requestedRightWidth: Double,
        wantsLeft: Bool,
        wantsRight: Bool
    ) -> ShellWidthAllocation {
        guard containerWidth >= supportedMinimumContentWidth else {
            let right: RightUtilityPresentation = wantsRight ? .railOnly(width: rightRailWidth) : .hidden
            let centerWidth = max(0, containerWidth - (wantsRight ? rightRailWidth : 0))
            return ShellWidthAllocation(leftWidth: nil, centerWidth: centerWidth, right: right)
        }

        guard wantsRight else {
            guard wantsLeft else {
                return ShellWidthAllocation(leftWidth: nil, centerWidth: containerWidth, right: .hidden)
            }

            let leftWidth = min(max(requestedLeftWidth, minimumLeftWidth), containerWidth - reservedCenterWidth)
            return ShellWidthAllocation(
                leftWidth: leftWidth,
                centerWidth: containerWidth - leftWidth,
                right: .hidden
            )
        }

        let requestedRightWidth = max(requestedRightWidth, minimumRightWidth)
        guard wantsLeft else {
            let rightWidth = min(requestedRightWidth, containerWidth - reservedCenterWidth)
            return ShellWidthAllocation(
                leftWidth: nil,
                centerWidth: containerWidth - rightWidth,
                right: .expanded(width: rightWidth)
            )
        }

        guard containerWidth >= reservedCenterWidth + minimumLeftWidth + minimumRightWidth else {
            let rightWidth = min(requestedRightWidth, containerWidth - reservedCenterWidth)
            return ShellWidthAllocation(
                leftWidth: nil,
                centerWidth: containerWidth - rightWidth,
                right: .expanded(width: rightWidth)
            )
        }

        let requestedLeftWidth = max(requestedLeftWidth, minimumLeftWidth)
        let availableSideWidth = containerWidth - reservedCenterWidth
        let requestedSideWidth = requestedLeftWidth + requestedRightWidth
        guard availableSideWidth < requestedSideWidth else {
            return ShellWidthAllocation(
                leftWidth: requestedLeftWidth,
                centerWidth: containerWidth - requestedSideWidth,
                right: .expanded(width: requestedRightWidth)
            )
        }

        let shortage = requestedSideWidth - availableSideWidth
        let leftReduction = min(shortage / 2, requestedLeftWidth - minimumLeftWidth)
        let remainingShortage = shortage - leftReduction
        let rightReduction = min(remainingShortage, requestedRightWidth - minimumRightWidth)
        return ShellWidthAllocation(
            leftWidth: requestedLeftWidth - leftReduction,
            centerWidth: reservedCenterWidth,
            right: .expanded(width: requestedRightWidth - rightReduction)
        )
    }
}
