import XCTest

final class MRTUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSessionsSmokeSupportsCancelAndCloseActions() throws {
        let app = XCUIApplication()
        app.launchArguments.append("MRT_UI_SMOKE")
        app.launch()

        app.buttons["tab.sessions"].tap()

        XCTAssertTrue(app.staticTexts["Sessions"].waitForExistence(timeout: 2))

        let cancelButton = app.buttons["session.cancel.session-main"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2))
        cancelButton.tap()
        XCTAssertTrue(app.staticTexts["Cancelled"].waitForExistence(timeout: 2))

        let closeButton = app.buttons["session.close.session-docs"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2))
        closeButton.tap()
        XCTAssertFalse(app.staticTexts["Docs Review"].waitForExistence(timeout: 1))
    }
}
