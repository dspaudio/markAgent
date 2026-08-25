import XCTest
@testable import ma

final class ShellWidthAllocatorTests: XCTestCase {
    func testRequested260And420AllocatesAtSupportedWidths() {
        XCTAssertEqual(
            allocation(width: 570),
            ShellWidthAllocation(leftWidth: nil, centerWidth: 320, right: .expanded(width: 250))
        )
        XCTAssertEqual(
            allocation(width: 980),
            ShellWidthAllocation(leftWidth: 250, centerWidth: 320, right: .expanded(width: 410))
        )
        XCTAssertEqual(
            allocation(width: 1_440),
            ShellWidthAllocation(leftWidth: 260, centerWidth: 760, right: .expanded(width: 420))
        )
    }

    func testDefensiveSubminimumWidthUsesRightRailOnly() {
        XCTAssertEqual(
            allocation(width: 569),
            ShellWidthAllocation(leftWidth: nil, centerWidth: 529, right: .railOnly(width: 40))
        )
    }

    func testLeftTransitionsFromCollapsedToExpandedAt790() {
        XCTAssertEqual(
            allocation(width: 789),
            ShellWidthAllocation(leftWidth: nil, centerWidth: 369, right: .expanded(width: 420))
        )
        XCTAssertEqual(
            allocation(width: 790),
            ShellWidthAllocation(leftWidth: 220, centerWidth: 320, right: .expanded(width: 250))
        )
    }

    func testEverySupportedVisibleRightBranchIsExpanded() {
        for width in [570.0, 789, 790, 980, 1_440] {
            for wantsLeft in [false, true] {
                let result = ShellWidthAllocator.allocate(
                    containerWidth: width,
                    requestedLeftWidth: 260,
                    requestedRightWidth: 420,
                    wantsLeft: wantsLeft,
                    wantsRight: true
                )

                guard case .expanded = result.right else {
                    return XCTFail("expected an expanded right body at \(width) with wantsLeft=\(wantsLeft)")
                }
            }
        }
    }

    private func allocation(width: Double) -> ShellWidthAllocation {
        ShellWidthAllocator.allocate(
            containerWidth: width,
            requestedLeftWidth: 260,
            requestedRightWidth: 420,
            wantsLeft: true,
            wantsRight: true
        )
    }
}
