import XCTest

final class EditorUITests: XCTestCase {
    func testColorFilterCatalogueAppliesToRealPhoto() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-photo"]; app.launch()
        XCTAssertTrue(app.images["photoPreview"].waitForExistence(timeout:30))
        let filters = app.buttons["tab_Фильтры"]
        for _ in 0..<4 { if filters.isHittable { break }; app.scrollViews["toolTabs"].swipeLeft() }
        XCTAssertTrue(filters.isHittable); filters.tap()
        let cinema = app.buttons["style_Cinematic"]
        XCTAssertTrue(cinema.waitForExistence(timeout:30))
        for _ in 0..<3 { if cinema.isHittable { break }; app.scrollViews["editorTools"].swipeUp() }
        XCTAssertTrue(cinema.isHittable); cinema.tap()
        let applied = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@","Применён фильтр «Кино»"),object:app.staticTexts["status"])
        XCTAssertEqual(XCTWaiter.wait(for:[applied],timeout:45),.completed)
        XCTAssertTrue(app.buttons["Отменить"].isEnabled)
        let screenshot = XCTAttachment(screenshot:app.screenshot());screenshot.name = "Каталог фильтров на реальном фото";screenshot.lifetime = .keepAlways;add(screenshot)
    }
    func testImportFixtureFilterUndoAndInformation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-photo"]
        app.launch()
        XCTAssertTrue(app.images["photoPreview"].waitForExistence(timeout:30))
        let studio = app.buttons["look_Студия"]
        app.scrollViews["editorTools"].swipeUp()
        XCTAssertTrue(studio.waitForExistence(timeout:30))
        studio.tap()
        let applied = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@","Применён образ «Студия»"),object:app.staticTexts["status"])
        XCTAssertEqual(XCTWaiter.wait(for:[applied],timeout:45),.completed)
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
