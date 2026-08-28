import XCTest
@testable import ma

final class ProviderBrandIconTests: XCTestCase {
    func testOfficialProviderMarksDecodeAsImages() throws {
        let claude = try XCTUnwrap(ProviderBrandAssets.image(for: .claude))
        let codex = try XCTUnwrap(ProviderBrandAssets.image(for: .codex))

        XCTAssertFalse(claude.isTemplate)
        XCTAssertTrue(codex.isTemplate)
        XCTAssertGreaterThan(claude.size.width, 0)
        XCTAssertGreaterThan(codex.size.width, 0)
    }
}
