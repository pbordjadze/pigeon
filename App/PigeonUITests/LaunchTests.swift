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
}
