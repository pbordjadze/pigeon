import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testFirstLaunchShowsTheEmptyRouteList() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "routes-empty"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Routes"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No Routes Yet"].exists)
    }

    @MainActor
    func testTheListShowsEachRouteAtItsStage() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "routes-list"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Harbor Office"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Quiet"].exists)
        XCTAssertTrue(app.staticTexts["1 clean drive to go"].exists)
    }

    @MainActor
    func testQuietShowsNoMapAndNoButtonsWhileMoving() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "drive-quiet"]
        app.launch()
        XCTAssertTrue(app.staticTexts["On Route"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.maps.firstMatch.exists)
        XCTAssertFalse(app.buttons["End Drive"].exists)
    }

    @MainActor
    func testACleanArrivalMovesTheRouteUp() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "arrival-clean"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Clean Drive"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Turns Only"].exists)
    }

    @MainActor
    func testADemoDriveWithAWrongTurnComesBackAndArrives() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "routes-empty"]
        app.launch()
        app.buttons["Try a Demo Drive"].firstMatch.tap()
        app.buttons["Turns Only"].firstMatch.tap()
        let wrongTurn = app.switches["Take a wrong turn"].firstMatch
        wrongTurn.switches.firstMatch.tap()
        XCTAssertEqual(wrongTurn.value as? String, "1")
        app.buttons["Start Demo Drive"].tap()
        XCTAssertTrue(app.buttons["Stop Demo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["You Left the Route"].waitForExistence(timeout: 150))
        XCTAssertTrue(app.staticTexts["Landmarks"].exists)
    }
}
