import XCTest

final class TrailDetailsTests: XCTestCase {
    func testSharedTrailLinkOpensFromMap() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-startInList"]
        app.launch()
        app.buttons["Show map"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
        app.open(URL(string: "herodirt://trail?lat=37.8765&lon=-122.6543&name=Deep%20Link%20Ridge")!)
        XCTAssertTrue(app.navigationBars["Deep Link Ridge"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Save"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Shared destination opened from map"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testSharedPlaceIDLinkResolvesFromMap() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-startInList"]
        app.launch()
        app.buttons["Show map"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
        app.open(URL(string: "herodirt://trail?placeID=I1234567890")!)
        XCTAssertTrue(app.navigationBars["Shared Place ID Trail"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Save"].exists)
    }

    func testSharedPlaceIDFailureShowsError() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-startInList"]
        app.launch()
        app.open(URL(string: "herodirt://trail?placeID=I9876543210")!)
        let error = app.alerts["Couldn't Open Trail"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        error.buttons["OK"].tap()
        XCTAssertTrue(app.navigationBars["My Trails"].exists)
        app.open(URL(string: "herodirt://trail?placeID=I1234567890")!)
        XCTAssertTrue(app.navigationBars["Shared Place ID Trail"].waitForExistence(timeout: 10))
    }

    func testTrailShareSheet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-startInList"]
        app.launch()
        let trail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rancho San Antonio")).firstMatch
        XCTAssertTrue(trail.waitForExistence(timeout: 10))
        trail.tap()
        app.buttons["Trail Options"].tap()
        let share = app.buttons["Share Trail"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        let copy = app.descendants(matching: .any).matching(identifier: "Copy").firstMatch
        if !copy.waitForExistence(timeout: 8) { print(app.debugDescription) }
        XCTAssertTrue(copy.exists)
        let previewTitle = app.otherElements["LP.CaptionBar.TopCaption"]
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(previewTitle.label.contains("Rancho San Antonio"))
        XCTAssertTrue(previewTitle.label.contains("Hero Dirt"))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Native trail share sheet"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "close", "Cancel"])).firstMatch.tap()
        XCTAssertTrue(app.buttons["Trail Options"].waitForExistence(timeout: 5))
    }

    func testNativeSearchInputInListAndMap() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-startInList"]
        app.launch()
        var field = app.searchFields.firstMatch
        if !field.isHittable { app.swipeDown() }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(field.frame.minY, app.frame.height / 2)
        field.tap()
        field.typeText("Rancho")
        XCTAssertEqual(field.value as? String, "Rancho")
        let main = XCTAttachment(screenshot: app.screenshot())
        main.name = "Native list search"
        main.lifetime = .keepAlways
        add(main)
        XCTAssertTrue(app.buttons["Dictate"].exists)
        app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Close", "close"])).firstMatch.tap()
        app.buttons["Show map"].tap()
        field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Arastradero")
        XCTAssertEqual(field.value as? String, "Arastradero")
        XCTAssertTrue(app.buttons["Dictate"].exists)
        let map = XCTAttachment(screenshot: app.screenshot())
        map.name = "Native map search"
        map.lifetime = .keepAlways
        add(map)
    }

    func testEmailFeedbackAtBottomOfAbout() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-startInList"]
        app.launch()
        app.buttons["About Hero Dirt"].tap()
        let email = app.buttons["Email Feedback"]
        for _ in 0..<5 where !email.isHittable { app.swipeUp() }
        XCTAssertTrue(email.isHittable)
        XCTAssertTrue(app.staticTexts["No GitHub account? Send feedback to irodrigo17@gmail.com."].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Email feedback"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testRainCalendarAndDailyForecast() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-startInList"]
        app.launch()
        let trail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rancho San Antonio")).firstMatch
        XCTAssertTrue(trail.waitForExistence(timeout: 10))
        trail.tap()
        let calendar = app.buttons["Rain Calendar"]
        for _ in 0..<8 where !calendar.isHittable { app.swipeUp() }
        XCTAssertTrue(calendar.isHittable)
        calendar.tap()
        XCTAssertTrue(app.navigationBars["Rain Calendar"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Next month"].isEnabled)
        let month = app.staticTexts["Rain calendar month"].label
        app.buttons["Previous month"].tap()
        XCTAssertNotEqual(app.staticTexts["Rain calendar month"].label, month)
        app.buttons["Next month"].tap()
        XCTAssertEqual(app.staticTexts["Rain calendar month"].label, month)
        let history = XCTAttachment(screenshot: app.screenshot())
        history.name = "Observed rain calendar"
        history.lifetime = .keepAlways
        add(history)
        app.buttons["Done"].tap()
        let forecast = app.buttons["Daily Rain Forecast"]
        for _ in 0..<5 where !forecast.isHittable { app.swipeUp() }
        XCTAssertTrue(forecast.isHittable)
        forecast.tap()
        XCTAssertTrue(app.navigationBars["Rain Forecast"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Today"].exists)
        let daily = XCTAttachment(screenshot: app.screenshot())
        daily.name = "Daily rain forecast"
        daily.lifetime = .keepAlways
        add(daily)
    }

    func testReorderTrails() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeServices", "-startInList"]
        app.launch()
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        let handles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder"))
        XCTAssertTrue(handles.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(handles.count, 2)
        let first = handles.element(boundBy: 0)
        let second = handles.element(boundBy: 1)
        first.press(forDuration: 0.5, thenDragTo: second)
        app.buttons["Done"].tap()
        let rancho = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rancho San Antonio")).firstMatch
        let arastradero = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Arastradero Preserve")).firstMatch
        XCTAssertLessThan(arastradero.frame.minY, rancho.frame.minY)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Reordered trails"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Show map"].tap()
        XCTAssertTrue(app.navigationBars["My Trails"].waitForExistence(timeout: 10))
        let mapRancho = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rancho San Antonio")).firstMatch
        let mapArastradero = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Arastradero Preserve")).firstMatch
        XCTAssertLessThan(mapArastradero.frame.minY, mapRancho.frame.minY)
    }

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
        app.launchArguments = ["-useFakeServices", "-slowDrivingETA", "-startInList"]
        app.launch()
        let trail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rancho San Antonio")).firstMatch
        XCTAssertTrue(trail.waitForExistence(timeout: 15))
        trail.tap()
        let directions = app.buttons["Driving Directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15))
        // Wait for an asynchronous estimate on first open, without pulling to refresh.
        let estimate = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "25"), object: directions
        )
        XCTAssertEqual(XCTWaiter.wait(for: [estimate], timeout: 15), .completed)
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
