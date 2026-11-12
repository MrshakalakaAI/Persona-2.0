import XCTest

final class EditorUITests: XCTestCase {
    func testImportFixtureFilterUndoAndInformation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-photo"]
        app.launch()
        XCTAssertTrue(app.images["photoPreview"].waitForExistence(timeout:30))
        let studio = app.buttons["look_Студия"]
        app.scrollViews["editorTools"].swipeUp()
        XCTAssertTrue(studio.waitForExistence(timeout:30))
        studio.tap()
        let undo = app.buttons["Отменить"]
        XCTAssertTrue(undo.isEnabled)
        undo.tap()
        XCTAssertFalse(undo.isEnabled)
        XCTAssertTrue(app.buttons["Повторить"].isEnabled)
        app.buttons["Повторить"].tap()
        XCTAssertTrue(undo.isEnabled)
        let screenshot = XCTAttachment(screenshot:app.screenshot())
        screenshot.name = "Реальный портрет — красота"; screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["О приложении"].tap()
        XCTAssertTrue(app.staticTexts["Точность лица"].waitForExistence(timeout:5))
        app.buttons["Готово"].tap()
        XCTAssertTrue(app.buttons["saveMedia"].exists)
    }
}

// Real portrait is loaded by the Debug launch fixture from NASA/scikit-image.
