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

        // Clicking the words opens the help, as a person would. SwiftUI folds the title
        // button into the disclosure triangle's accessibility element; its centre is the title.
        let help = settings.disclosureTriangles["How do I find my token?"]
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

    @MainActor
    func testMenuBarWindowShowsItsControls() throws {
        let app = launch()
        let window = try openMenuBarWindow(app)
        XCTAssertTrue(window.buttons["Open Curator"].exists)
        XCTAssertTrue(window.buttons["Settings…"].exists)
        XCTAssertTrue(window.buttons["Quit Curator"].exists)
        keepScreenshot(of: window, named: "Menu bar window, not connected")
    }

    // MARK: Live (needs a Plex server)

    @MainActor
    func testMenuBarWindowListsTheLatestImports() throws {
        let app = try launchWithPlex()
        XCTAssertTrue(app.buttons.matching(identifier: "poster").firstMatch.waitForExistence(timeout: 30))
        let window = try openMenuBarWindow(app)
        let rows = window.buttons.matching(identifier: "menuBarRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(rows.count, 5)
        // The list must not spill over the header or the footer: every visible row sits below
        // the refresh button and above the footer's buttons.
        let top = app.buttons["menuBarRefresh"].frame.maxY
        let bottom = app.buttons["menuBarOpen"].frame.minY
        for index in 0..<rows.count where rows.element(boundBy: index).isHittable {
            let frame = rows.element(boundBy: index).frame
            XCTAssertGreaterThanOrEqual(frame.minY, top, "row \(index) overlaps the header")
            XCTAssertLessThanOrEqual(frame.maxY, bottom, "row \(index) overlaps the footer")
        }
        keepScreenshot(of: window, named: "Menu bar window, connected")
    }

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

    /// The TMDB key from .env is really accepted, so artwork comes from TMDB rather than silently
    /// falling back to Plex's posters.
    @MainActor
    func testTMDBKeyIsAccepted() throws {
        try XCTSkipIf((ProcessInfo.processInfo.environment["CURATOR_TMDB_API_KEY"] ?? "").isEmpty, "No TMDB key configured for this run")
        let app = try launchWithPlex()
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["Curator Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        XCTAssertTrue(text(containing: "TMDB key accepted", in: settings).waitForExistence(timeout: 20),
                      "TMDB didn't accept the key; artwork would fall back to Plex")
    }

    /// Sorting Movies by release date really reorders the posters, both ways.
    @MainActor
    func testSortingByReleaseDate() throws {
        let app = try launchWithPlex()
        XCTAssertTrue(app.buttons.matching(identifier: "poster").firstMatch.waitForExistence(timeout: 30))
        let movies = app.outlines.staticTexts["Movies"]
        XCTAssertTrue(movies.waitForExistence(timeout: 10))
        movies.click()

        chooseSort(app, "Release Date")
        chooseSort(app, "Oldest First")
        let oldestFirst = try years(ofFirst: 4, in: app)
        XCTAssertEqual(oldestFirst, oldestFirst.sorted(), "not oldest first: \(oldestFirst)")

        chooseSort(app, "Newest First")
        let newestFirst = try years(ofFirst: 4, in: app)
        XCTAssertEqual(newestFirst, newestFirst.sorted(by: >), "not newest first: \(newestFirst)")
        XCTAssertNotEqual(oldestFirst, newestFirst)

        chooseSort(app, "Title")   // leave the remembered sort as it was
    }

    /// Search results can be sorted with the same Sort menu.
    @MainActor
    func testSortingSearchResultsByReleaseDate() throws {
        let app = try launchWithPlex()
        XCTAssertTrue(app.buttons.matching(identifier: "poster").firstMatch.waitForExistence(timeout: 30))
        app.typeKey("f", modifierFlags: .command)
        app.typeText("the")
        XCTAssertTrue(app.staticTexts["Titles"].waitForExistence(timeout: 15), "no title matches for \"the\"")

        chooseSort(app, "Release Date")
        chooseSort(app, "Oldest First")
        let oldestFirst = try years(ofFirst: 4, in: app)
        XCTAssertGreaterThanOrEqual(oldestFirst.count, 2)
        XCTAssertEqual(oldestFirst, oldestFirst.sorted(), "search results not oldest first: \(oldestFirst)")

        chooseSort(app, "Newest First")
        let newestFirst = try years(ofFirst: 4, in: app)
        XCTAssertEqual(newestFirst, newestFirst.sorted(by: >), "search results not newest first: \(newestFirst)")

        chooseSort(app, "Title")
    }

    /// Reproduces the 0.0.1 crash: resizing the window while the poster grid and inspector are
    /// showing threw `_postWindowNeedsUpdateConstraints` inside AppKit's layout pass.
    @MainActor
    func testResizingTheWindowKeepsTheAppRunning() throws {
        let app = try launchWithPlex()
        let posters = app.buttons.matching(identifier: "poster")
        XCTAssertTrue(posters.firstMatch.waitForExistence(timeout: 30))
        posters.firstMatch.click()   // opens the inspector, which narrows the grid
        XCTAssertTrue(app.staticTexts["detailTitle"].waitForExistence(timeout: 10))

        let window = app.windows.matching(identifier: "main").firstMatch
        XCTAssertTrue(window.exists)
        for (dx, dy) in [(-420.0, -180.0), (380.0, 160.0), (-250.0, 0.0), (300.0, 60.0), (-500.0, -200.0), (500.0, 200.0)] {
            let before = window.frame.size
            let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -3, dy: -3))
            // A slow drag, so AppKit runs many live-resize layout passes, like a person resizing.
            corner.press(forDuration: 0.2, thenDragTo: corner.withOffset(CGVector(dx: dx, dy: dy)),
                         withVelocity: .slow, thenHoldForDuration: 0.2)
            XCTAssertEqual(app.state, .runningForeground, "Curator stopped running while resizing")
            XCTAssertNotEqual(window.frame.size, before, "the drag didn't resize the window")
        }
        XCTAssertTrue(posters.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["detailTitle"].exists)
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
    private func chooseSort(_ app: XCUIApplication, _ item: String) {
        let menu = app.toolbars.menuButtons["Sort"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no Sort menu")
        menu.click()
        let choice = app.menuItems[item]
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "no \(item) in the Sort menu")
        choice.click()
    }

    /// The release years shown under the first posters, read from their subtitles.
    @MainActor
    private func years(ofFirst count: Int, in app: XCUIApplication) throws -> [Int] {
        let posters = app.buttons.matching(identifier: "poster")
        XCTAssertTrue(posters.firstMatch.waitForExistence(timeout: 20))
        let pattern = try Regex(#"\b(1[89]|20)\d{2}\b"#)
        return (0..<min(count, posters.count)).compactMap { index in
            let label = posters.element(boundBy: index).label
            return label.matches(of: pattern).last.flatMap { Int(label[$0.range]) }
        }
    }

    /// Clicks Curator's status item and returns the window it opens.
    @MainActor
    private func openMenuBarWindow(_ app: XCUIApplication) throws -> XCUIElement {
        let item = app.statusItems.firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "no status item")
        item.click()
        let open = app.buttons["Open Curator"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "the menu bar window didn't open")
        let window = app.windows.containing(.button, identifier: "Open Curator").firstMatch
        return window.exists ? window : app
    }

    @MainActor
    private func keepScreenshot(of element: XCUIElement, named name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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
