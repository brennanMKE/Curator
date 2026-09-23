import XCTest

/// Curator's UI tests. These run only inside a Tart guest, through
/// `scripts/run-ui-tests-vm.sh`; the target refuses to build on a host Mac.
///
/// Offline tests always run. Live tests need a Plex server: the run script passes
/// `CURATOR_PLEX_URL`, `CURATOR_PLEX_TOKEN` and `CURATOR_TMDB_API_KEY` to the test runner,
/// and the tests hand them to the app. Without them the live tests are skipped.
final class CuratorUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Offline

    @MainActor
    func testFirstLaunchAsksToConnect() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Connect to Plex"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Open Settings…"].exists)
    }

    @MainActor
    func testSettingsExplainHowToFindTheToken() throws {
        let app = launch()
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["Curator Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))

        // Clicking the words opens the help, as a person would.
        let help = settings.buttons["How do I find my token?"]
        XCTAssertTrue(help.waitForExistence(timeout: 5), "token help missing")
        help.click()
        XCTAssertTrue(text(containing: "View XML", in: settings).waitForExistence(timeout: 5), "token help didn't open")
        XCTAssertTrue(text(containing: "X-Plex-Token", in: settings).exists)
    }

    @MainActor
    func testUnreachableServerExplainsTheProblem() throws {
        // Loopback port 1 refuses at once, with no local-network prompt.
        let app = launch(environment: ["CURATOR_PLEX_URL": "http://127.0.0.1:1", "CURATOR_PLEX_TOKEN": "not-a-token"])
        XCTAssertTrue(text(containing: "Couldn't reach the Plex server", in: app).waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Try Again"].exists)
    }

    // MARK: Live (needs a Plex server)

    @MainActor
    func testRecentlyAddedShowsPostersAndDetails() throws {
        let app = try launchWithPlex()
        let poster = app.buttons.matching(identifier: "poster").firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 30), "no posters: is the Plex server reachable from the guest?")
        poster.click()
        XCTAssertTrue(app.staticTexts["detailTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Open in Plex"].exists)
    }

    @MainActor
    func testArrowKeysMoveSelectionAndSpacePreviews() throws {
        let app = try launchWithPlex()
        let posters = app.buttons.matching(identifier: "poster")
        XCTAssertTrue(posters.firstMatch.waitForExistence(timeout: 30))
        try XCTSkipIf(posters.count < 2, "need two titles to move between")

        posters.firstMatch.click()
        // On macOS a text's contents are its accessibility value, not its label.
        let title = app.staticTexts["detailTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let first = title.value as? String ?? ""
        XCTAssertFalse(first.isEmpty)

        app.typeKey(.rightArrow, modifierFlags: [])
        let moved = NSPredicate(format: "value != %@", first)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: moved, evaluatedWith: title)], timeout: 10), .completed)

        app.typeKey(.space, modifierFlags: [])
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Space didn't open the preview")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(close.waitForNonExistence(timeout: 10))
    }

    @MainActor
    func testSearchShowsNoResultsForAnUnknownTitle() throws {
        let app = try launchWithPlex()
        XCTAssertTrue(app.buttons.matching(identifier: "poster").firstMatch.waitForExistence(timeout: 30))
        app.typeKey("f", modifierFlags: .command)
        app.typeText("zzqxnotamovie")
        XCTAssertTrue(text(containing: "No Results for", in: app).waitForExistence(timeout: 15))
    }

    // MARK: Helpers

    @MainActor
    private func launch(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CURATOR_UI_TEST"] = "1"
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launchArguments += ["-viewMode", "grid"]
        app.launch()
        return app
    }

    @MainActor
    private func launchWithPlex() throws -> XCUIApplication {
        let environment = ProcessInfo.processInfo.environment
        guard let url = environment["CURATOR_PLEX_URL"], !url.isEmpty,
              let token = environment["CURATOR_PLEX_TOKEN"], !token.isEmpty
        else {
            throw XCTSkip("No Plex server configured for this run")
        }
        return launch(environment: [
            "CURATOR_PLEX_URL": url,
            "CURATOR_PLEX_TOKEN": token,
            "CURATOR_TMDB_API_KEY": environment["CURATOR_TMDB_API_KEY"] ?? "",
        ])
    }

    @MainActor
    private func text(containing fragment: String, in element: XCUIElement) -> XCUIElement {
        element.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", fragment, fragment))
            .firstMatch
    }
}
