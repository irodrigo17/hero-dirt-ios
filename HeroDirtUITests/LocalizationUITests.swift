import XCTest

final class LocalizationUITests: XCTestCase {
    func testLocalizedTrailAndSettingsFlows() {
        continueAfterFailure = false
        let cases: [(String, String, String, String, String, String, String)] = [
            ("es", "es_ES", "Mis senderos", "Estado del sendero", "Ajustes del sendero", "Ajustes", "Cancelar"),
            ("fr", "fr_FR", "Mes sentiers", "État du sentier", "Réglages du sentier", "Réglages", "Annuler"),
            ("de", "de_DE", "Meine Trails", "Trailzustand", "Traileinstellungen", "Anpassen", "Abbrechen"),
            ("pt-BR", "pt_BR", "Minhas trilhas", "Condições da trilha", "Ajustes da trilha", "Ajustes", "Cancelar"),
            ("ja", "ja_JP", "マイトレイル", "トレイルの路面状況", "トレイル設定", "トレイル設定", "キャンセル")
        ]
        for (language, locale, home, condition, settings, tune, cancel) in cases {
            let app = XCUIApplication()
            app.launchArguments = ["-useFakeServices", "-startInList", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            app.launch()
            XCTAssertTrue(app.navigationBars[home].waitForExistence(timeout: 10), language)
            let trail = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rancho San Antonio")).firstMatch
            XCTAssertTrue(trail.waitForExistence(timeout: 10))
            trail.tap()
            XCTAssertTrue(app.staticTexts[condition].waitForExistence(timeout: 10), language)
            attach(app, name: "\(language) trail details")
            app.buttons["Trail Options"].tap()
            XCTAssertTrue(app.buttons[settings].waitForExistence(timeout: 5), language)
            app.buttons[settings].tap()
            XCTAssertTrue(app.navigationBars[tune].waitForExistence(timeout: 5), language)
            attach(app, name: "\(language) soil settings")
            app.buttons[cancel].tap()
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars[home].waitForExistence(timeout: 5))
            app.navigationBars.buttons.firstMatch.tap()
            let about = ["es": "Acerca de", "fr": "À propos", "de": "Über die App", "pt-BR": "Sobre", "ja": "このアプリについて"][language]!
            XCTAssertTrue(app.navigationBars[about].waitForExistence(timeout: 5), language)
            attach(app, name: "\(language) about and units")
            app.terminate()
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
