import XCTest
@testable import ma

final class RightUtilityRoutingTests: XCTestCase {
    func testSelectionRevealsRequestedOuterTool() {
        var route = RightUtilityRouteState()

        XCTAssertNil(route.handle(.select(.timeline)))

        XCTAssertTrue(route.isVisible)
        XCTAssertEqual(route.selectedTab, .timeline)
    }

    func testSnippetRevealSelectsSnippets() {
        var route = RightUtilityRouteState()

        XCTAssertNil(route.handle(.showSnippets))

        XCTAssertTrue(route.isVisible)
        XCTAssertEqual(route.selectedTab, .snippets)
    }

    func testFileAndContentSearchRevealFileBrowserAndEmitOneFocusMode() {
        for mode in [SidebarSearchMode.files, .grep] {
            var route = RightUtilityRouteState()
            var focusedModes: [SidebarSearchMode] = []

            if let focusMode = route.handle(.focusSearch(mode)) {
                focusedModes.append(focusMode)
            }

            XCTAssertTrue(route.isVisible)
            XCTAssertEqual(route.selectedTab, .fileBrowser)
            XCTAssertEqual(focusedModes, [mode])
        }
    }

    func testVisibilityTogglePreservesSelection() {
        var route = RightUtilityRouteState(isVisible: true, selectedTab: .fileBrowser)

        XCTAssertNil(route.handle(.toggleVisibility))
        XCTAssertFalse(route.isVisible)
        XCTAssertEqual(route.selectedTab, .fileBrowser)

        XCTAssertNil(route.handle(.toggleVisibility))
        XCTAssertTrue(route.isVisible)
        XCTAssertEqual(route.selectedTab, .fileBrowser)
    }

    func testRoutedBodiesRemainExpandedAtSupportedBoundaryWidths() {
        let actions: [(String, RightUtilityAction)] = [
            ("selection", .select(.timeline)),
            ("snippets", .showSnippets),
            ("file search", .focusSearch(.files)),
            ("content search", .focusSearch(.grep)),
        ]

        for width in [570.0, 789, 790] {
            for (name, action) in actions {
                var route = RightUtilityRouteState()
                _ = route.handle(action)
                let allocation = ShellWidthAllocator.allocate(
                    containerWidth: width,
                    requestedLeftWidth: 260,
                    requestedRightWidth: 420,
                    wantsLeft: true,
                    wantsRight: route.isVisible
                )

                guard case .expanded = allocation.right else {
                    return XCTFail("\(name) body is not mounted at supported width \(width)")
                }
            }
        }
    }
}
