import XCTest

final class FilesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFilesTabShowsRootEntries() throws {
        let app = XCUIApplication()
        app.launchArguments.append("MRT_UI_SMOKE_FILES")
        app.launch()

        app.buttons["tab.files"].tap()

        XCTAssertTrue(app.staticTexts["Current Path"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["files.entry.Sources"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["files.entry.notes.txt"].waitForExistence(timeout: 2))
        app.buttons["files.entry.notes.txt"].tap()
    }
}
