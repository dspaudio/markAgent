import AppKit
import XCTest
@testable import ma

final class WindowFramePolicyTests: XCTestCase {
    private let minimumFrameSize = NSSize(width: 570, height: 320)

    func testSubminimumSavedFrameExpandsToMinimumSize() {
        let savedFrame = NSRect(x: 40, y: 100, width: 480, height: 240)

        let normalized = WindowFramePolicy.normalizedSavedFrame(
            savedFrame,
            minimumFrameSize: minimumFrameSize
        )

        XCTAssertEqual(normalized.size, minimumFrameSize)
        XCTAssertEqual(normalized.origin.x, savedFrame.origin.x)
    }

    func testHeightGrowthPreservesSavedTopEdge() {
        let savedFrame = NSRect(x: 40, y: 100, width: 640, height: 240)

        let normalized = WindowFramePolicy.normalizedSavedFrame(
            savedFrame,
            minimumFrameSize: minimumFrameSize
        )

        XCTAssertEqual(normalized.height, minimumFrameSize.height)
        XCTAssertEqual(normalized.maxY, savedFrame.maxY)
    }

    func testValidSavedFrameIsUnchanged() {
        let savedFrame = NSRect(x: 40, y: 100, width: 640, height: 480)

        XCTAssertEqual(
            WindowFramePolicy.normalizedSavedFrame(savedFrame, minimumFrameSize: minimumFrameSize),
            savedFrame
        )
    }

    func testVisibilityReceivesNormalizedFrame() {
        let savedFrame = NSRect(x: 40, y: 100, width: 480, height: 240)
        var inspectedFrame: NSRect?

        let restored = WindowFramePolicy.restoredSavedFrame(
            savedFrame,
            minimumFrameSize: minimumFrameSize
        ) { frame in
            inspectedFrame = frame
            return true
        }

        XCTAssertEqual(inspectedFrame?.size, minimumFrameSize)
        XCTAssertEqual(restored?.size, minimumFrameSize)
    }
}
