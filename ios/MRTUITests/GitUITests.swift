import XCTest

final class GitUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testGitTabShowsChangedFilesAndDiff() throws {
        let app = XCUIApplication()
        app.launchArguments.append("MRT_UI_SMOKE_GIT")
        app.launch()

        app.buttons["tab.git"].tap()

        XCTAssertTrue(app.staticTexts["Repository Summary"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Sources/App.swift"].waitForExistence(timeout: 2))

        app.buttons["git.file.Sources_App.swift"].tap()

        XCTAssertTrue(app.staticTexts["diff --git a/Sources/App.swift b/Sources/App.swift"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["+let enabled = true"].waitForExistence(timeout: 2))
    }
}
