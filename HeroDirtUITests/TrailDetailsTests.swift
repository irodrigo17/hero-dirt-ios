import XCTest

final class TrailDetailsTests: XCTestCase {
    func testMapUsesTrailCards() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-startInList"]
        app.launch()
        app.buttons["Show map"].tap()
        XCTAssertTrue(app.navigationBars["My Trails"].waitForExistence(timeout: 10))
        let trail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rancho San Antonio")).firstMatch
        XCTAssertTrue(trail.waitForExistence(timeout: 10))
        XCTAssertTrue(trail.label.contains("Today:"))
        XCTAssertTrue(trail.label.contains("last rain"))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Map sheet trail cards"
        shot.lifetime = .keepAlways
        add(shot)
        trail.tap()
        XCTAssertTrue(app.buttons["Trail Options"].waitForExistence(timeout: 10))
    }

    func testSavingFromInlineActionRow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-startInList"]
        app.launch()
        app.buttons["Show map"].tap()
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2)).press(forDuration: 1)
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 15))
        let directions = app.buttons["Driving Directions"]
        let more = app.buttons["Trail Options"]
        XCTAssertEqual(save.frame.minY, directions.frame.minY, accuracy: 2)
        XCTAssertEqual(save.frame.width, directions.frame.width, accuracy: 2)
        XCTAssertEqual(save.frame.width, more.frame.width, accuracy: 2)
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Before saving"
        before.lifetime = .keepAlways
        add(before)
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
        wait(for: [ready], timeout: 30)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5))
        XCTAssertTrue(directions.exists)
        XCTAssertTrue(more.exists)
        XCTAssertEqual(directions.frame.width, more.frame.width, accuracy: 2)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "After saving"
        after.lifetime = .keepAlways
        add(after)
    }

    /// Exercise production startup too: fake services bypass iCloud setup.
    func testNormalLaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-startInList"]
        app.launch()
        XCTAssertTrue(app.navigationBars["My Trails"].waitForExistence(timeout: 15))
        app.buttons["About Hero Dirt"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["My Trails"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testDrivingETAOpensMaps() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-startInList"]
        app.launch()
        let trail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rancho San Antonio")).firstMatch
        XCTAssertTrue(trail.waitForExistence(timeout: 15))
        trail.tap()
        let directions = app.buttons["Driving Directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15))
        XCTAssertTrue(directions.label.contains("25"))
        directions.tap()
        XCTAssertTrue(XCUIApplication(bundleIdentifier: "com.apple.Maps").wait(for: .runningForeground, timeout: 10))
    }

    func testDrivingETAFallback() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-noDrivingETA", "-startInList"]
        app.launch()
        let trail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rancho San Antonio")).firstMatch
        XCTAssertTrue(trail.waitForExistence(timeout: 15))
        trail.tap()
        let directions = app.buttons["Driving Directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15))
        XCTAssertEqual(directions.label, "Directions")
        XCTAssertTrue(directions.isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testWebsiteOpensBrowser() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-startInList"]
        app.launch()
        let trail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rancho San Antonio")).firstMatch
        XCTAssertTrue(trail.waitForExistence(timeout: 15))
        trail.tap()
        let options = app.buttons["Trail Options"]
        XCTAssertTrue(options.waitForExistence(timeout: 15))
        options.tap()
        let website = app.buttons["Website"]
        XCTAssertTrue(website.waitForExistence(timeout: 3))
        website.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10))
    }

    func testTrailWithoutWebsite() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-startInList"]
        app.launch()
        let trail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Arastradero Preserve")).firstMatch
        XCTAssertTrue(trail.waitForExistence(timeout: 15))
        trail.tap()
        let options = app.buttons["Trail Options"]
        XCTAssertTrue(options.waitForExistence(timeout: 15))
        options.tap()
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Website"].exists)
    }

    func testSavedTrailOptions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-startInList"]
        app.launch()
        app.buttons["Allow While Using App"].tapIfPresent()
        let trail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rancho San Antonio")).firstMatch
        XCTAssertTrue(trail.waitForExistence(timeout: 15))
        trail.tap()
        let options = app.buttons["Trail Options"]
        XCTAssertTrue(options.waitForExistence(timeout: 15))
        let directions = app.buttons["Driving Directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 5))
        XCTAssertTrue(directions.label.contains("25"))
        XCTAssertFalse(directions.label == "Directions")
        XCTAssertEqual(options.label, "More")
        XCTAssertEqual(directions.frame.minY, options.frame.minY, accuracy: 2)
        XCTAssertEqual(directions.frame.width, options.frame.width, accuracy: 2)
        XCTAssertFalse(app.navigationBars.buttons["Trail Options"].exists)
        XCTAssertFalse(app.navigationBars.staticTexts["Park"].exists)
        XCTAssertFalse(app.buttons["Saved"].exists)
        XCTAssertFalse(app.buttons["Save"].exists)
        options.tap()
        XCTAssertTrue(app.buttons["Website"].waitForExistence(timeout: 3))
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
