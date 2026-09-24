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

    // MARK: Playlists (live; every playlist made is named "Curator UI Test …" and deleted)

    /// Context menu → New Playlist…, then Add to Playlist from the recent shortcuts, Undo,
    /// open the playlist, remove an entry with Delete, and delete the playlist.
    @MainActor
    func testPlaylistFromContextMenu() async throws {
        let api = try XCTUnwrap(PlexTestAPI(), "no Plex server configured")
        await api.deleteTestPlaylists()
        addTeardownBlock { await api.deleteTestPlaylists() }

        let app = try launchWithPlex()
        let posters = app.buttons.matching(identifier: "poster")
        XCTAssertTrue(posters.element(boundBy: 1).waitForExistence(timeout: 30))
        let name = PlexTestAPI.uniqueName()

        // New Playlist… starts the playlist with the first poster's title.
        chooseFromContextMenu(of: posters.element(boundBy: 0), in: app, path: ["Add to Playlist", "New Playlist…"])
        let field = app.textFields["newPlaylistName"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(name)
        app.buttons["Create"].click()
        XCTAssertTrue(banner(containing: "Created \(name)", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(app.outlines.staticTexts[name].waitForExistence(timeout: 15), "not in the sidebar")

        // The new playlist is a recent shortcut in Add to Playlist.
        chooseFromContextMenu(of: posters.element(boundBy: 1), in: app, path: ["Add to Playlist", name])
        XCTAssertTrue(banner(containing: "to \(name)", in: app).waitForExistence(timeout: 15))
        try await waitForCount(2, of: name, api: api)

        // Undo takes it back out.
        app.buttons["Undo"].click()
        try await waitForCount(1, of: name, api: api)

        // Adding the first title again is reported, not duplicated.
        chooseFromContextMenu(of: posters.element(boundBy: 0), in: app, path: ["Add to Playlist", name])
        XCTAssertTrue(banner(containing: "already in \(name)", in: app).waitForExistence(timeout: 15))

        // Add the second again, then open the playlist and remove one with Delete.
        chooseFromContextMenu(of: posters.element(boundBy: 1), in: app, path: ["Add to Playlist", name])
        try await waitForCount(2, of: name, api: api)
        app.outlines.staticTexts[name].click()
        let entries = app.descendants(matching: .any).matching(identifier: "playlistEntry")
        XCTAssertTrue(entries.element(boundBy: 1).waitForExistence(timeout: 15))
        XCTAssertEqual(entries.count, 2)
        entries.element(boundBy: 0).click()
        app.typeKey(.delete, modifierFlags: [])
        try await waitForCount(1, of: name, api: api)

        // Delete the playlist from its toolbar menu.
        let menu = app.toolbars.menuButtons["playlistMenu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.click()
        app.menuItems["Delete Playlist…"].click()
        let confirm = app.buttons["Delete Playlist"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.click()
        XCTAssertTrue(banner(containing: "Deleted \(name)", in: app).waitForExistence(timeout: 15))
        let gone = try await api.playlist(named: name)
        XCTAssertNil(gone, "the playlist is still on the server")
    }

    /// Dragging a poster onto a playlist in the sidebar adds it.
    @MainActor
    func testDragPosterOntoSidebarPlaylist() async throws {
        let api = try XCTUnwrap(PlexTestAPI(), "no Plex server configured")
        await api.deleteTestPlaylists()
        addTeardownBlock { await api.deleteTestPlaylists() }
        let name = PlexTestAPI.uniqueName()
        let keys = try await api.movieRatingKeys(1)
        let first = try XCTUnwrap(keys.first)
        try await api.createPlaylist(named: name, ratingKey: first)

        let app = try launchWithPlex()
        let posters = app.buttons.matching(identifier: "poster")
        XCTAssertTrue(posters.firstMatch.waitForExistence(timeout: 30))
        let target = app.outlines.staticTexts[name]
        XCTAssertTrue(target.waitForExistence(timeout: 15), "the new playlist isn't in the sidebar")

        // Recently Added's first poster is a different movie from the library's first title.
        posters.firstMatch.press(forDuration: 0.6, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.4)
        XCTAssertTrue(banner(containing: "to \(name)", in: app).waitForExistence(timeout: 15), "no confirmation after the drop")
        try await waitForCount(2, of: name, api: api)
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

    /// Right-clicks an element and follows a path through the context menu and its submenus.
    @MainActor
    private func chooseFromContextMenu(of element: XCUIElement, in app: XCUIApplication, path: [String]) {
        element.rightClick()
        for (index, title) in path.enumerated() {
            let item = app.menuItems[title].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "no \"\(title)\" in the context menu")
            if index < path.count - 1 { item.hover() } else { item.click() }
        }
    }

    @MainActor
    private func banner(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "identifier == 'playlistBanner' AND (label CONTAINS %@ OR value CONTAINS %@)", text, text)).firstMatch
    }

    /// Waits for the server to report `count` items in the named playlist.
    private func waitForCount(_ count: Int, of name: String, api: PlexTestAPI, timeout: Duration = .seconds(15)) async throws {
        let deadline = ContinuousClock.now + timeout
        var last = -1
        while ContinuousClock.now < deadline {
            last = try await api.playlist(named: name)?.count ?? -1
            if last == count { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        XCTFail("\(name) has \(last) items on the server, expected \(count)")
    }

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
