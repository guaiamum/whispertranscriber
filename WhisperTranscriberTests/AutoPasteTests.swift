import XCTest
@testable import WhisperTranscriber

@MainActor
final class AutoPasteTests: XCTestCase {

    func testOwnProcessInFrontCountsAsFocused() {
        XCTAssertTrue(isOwnAppFocused(frontmostPID: 42, ownPID: 42, hasKeyWindow: false))
    }

    func testOwnKeyWindowCountsAsFocused() {
        XCTAssertTrue(isOwnAppFocused(frontmostPID: 7, ownPID: 42, hasKeyWindow: true))
    }

    func testAnotherAppInFrontIsNotOwnApp() {
        XCTAssertFalse(isOwnAppFocused(frontmostPID: 7, ownPID: 42, hasKeyWindow: false))
        XCTAssertFalse(isOwnAppFocused(frontmostPID: nil, ownPID: 42, hasKeyWindow: false))
    }

    func testPasteIsSkippedWhileOwnAppHasFocus() {
        XCTAssertEqual(pasteIntoFrontmostApp(ownAppFocused: true), .skippedOwnApp)
    }
}
