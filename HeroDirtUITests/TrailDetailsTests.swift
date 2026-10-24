import XCTest

final class TrailDetailsTests: XCTestCase {
    func testSavedTrailOptions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices"]
        app.launch()
        app.buttons["Allow While Using App"].tapIfPresent()
        let trail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rancho San Antonio")).firstMatch
        XCTAssertTrue(trail.waitForExistence(timeout: 15))
        trail.tap()
        let options = app.buttons["Trail Options"]
        XCTAssertTrue(options.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Saved"].exists)
        XCTAssertFalse(app.buttons["Save"].exists)
        options.tap()
        app.buttons["Rename"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 30) + "Test Trail")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Test Trail"].waitForExistence(timeout: 3))
        options.tap()
        app.buttons["Trail Settings"].tap()
        XCTAssertTrue(app.navigationBars["Tune This Trail"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        options.tap()
        app.buttons["Delete Trail"].tap()
        XCTAssertTrue(app.sheets["Delete this trail?"].waitForExistence(timeout: 3))
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            app.otherElements["PopoverDismissRegion"].tap()
        }
        XCTAssertTrue(options.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
        options.tap()
        app.buttons["Delete Trail"].tap()
        let confirmation = app.sheets["Delete this trail?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Delete Trail"].tap()
        XCTAssertTrue(app.navigationBars["My Trails"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Test Trail")).firstMatch.exists)
    }
}

private extension XCUIElement {
    func tapIfPresent() {
        if waitForExistence(timeout: 2) { tap() }
    }
}
