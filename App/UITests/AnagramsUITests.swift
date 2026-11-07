import XCTest

final class AnagramsUITests: XCTestCase {
    /// Demo sentence → board → tap "silent" → Check (letters left over: "Not yet").
    @MainActor
    func testBuildAndCheck() throws {
        let app = launch(["-demo"])
        tapMakeAnagram(app)
        shot(app, "1-board")

        for letter in ["S", "I", "L", "E", "N", "T"] {
            app.staticTexts.matching(identifier: letter).firstMatch.tap()
        }
        shot(app, "2-built")

        app.buttons["Check"].tap()
        XCTAssertTrue(app.staticTexts["Not yet"].waitForExistence(timeout: 5))
        shot(app, "3-verdict")
    }

    /// A long word must stay inside the screen, and a plain drag moves a single block.
    @MainActor
    func testLongWordsFitAndBlocksDrag() throws {
        let app = launch(["-demoText", "Donaudampfschifffahrtsgesellschaft precipitevolissimevolmente ok"])
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(app.staticTexts.matching(identifier: "D").firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        shot(app, "4-long-listening")
        for block in app.staticTexts.allElementsBoundByIndex where block.label.count == 1 {
            XCTAssertTrue(window.contains(block.frame), "\(block.label) at \(block.frame) is off screen")
        }

        tapMakeAnagram(app)
        let before = app.staticTexts.matching(identifier: "K").firstMatch.frame
        // a plain drag (no long press) from the tray into the lower half
        let start = app.staticTexts.matching(identifier: "K").firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(1)
        shot(app, "5-dragged")
        let moved = app.staticTexts.matching(identifier: "K").firstMatch.frame
        XCTAssertGreaterThan(moved.midY, before.midY + 100, "K should have moved down to the anagram area")
    }

    /// The sentence can be typed instead of said.
    @MainActor
    func testTypeASentence() throws {
        let app = launch(["-demoText", "", "-meaning", "yes"])
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Dormitory\n")
        XCTAssertTrue(app.staticTexts.matching(identifier: "Y").firstMatch.waitForExistence(timeout: 3))
        shot(app, "6-typed")
        app.buttons["Make anagram"].tap()
        for letter in ["D", "I", "R", "T", "Y"] { app.staticTexts.matching(identifier: letter).firstMatch.tap() }
        app.buttons["Space"].tap()
        for letter in ["R", "O", "O", "M"] { app.staticTexts.matching(identifier: letter).firstMatch.tap() }
        shot(app, "7-typed-built")
        app.buttons["Check"].tap()
        XCTAssertTrue(app.staticTexts["Yes! It's an anagram."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["It makes sense!"].waitForExistence(timeout: 5))
        shot(app, "7-typed-meaning")
    }

    /// The home menu leads to Help and back.
    @MainActor
    func testHomeMenu() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(2)
        shot(app, "0-home")
        app.buttons["Help"].tap()
        XCTAssertTrue(app.staticTexts["Make anagram"].waitForExistence(timeout: 3))
        shot(app, "0-help")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Game"].waitForExistence(timeout: 3))
    }

    /// Against the clock: a word and a full anagram score; Stop shows the result.
    @MainActor
    func testAgainstTheClock() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoText", ""]
        app.launch()
        app.buttons["Game"].tap()
        app.buttons["Against the clock"].tap()
        XCTAssertFalse(app.staticTexts["Speak in any language"].exists)
        XCTAssertFalse(app.buttons["Give me a sentence"].exists)
        typeSentence(app, "Listen")
        shot(app, "8-clock-sentence")
        tapMakeAnagram(app)
        for letter in ["S", "I", "L", "E", "N", "T"] { app.staticTexts.matching(identifier: letter).firstMatch.tap() }
        app.buttons["Check"].tap()
        XCTAssertTrue(app.staticTexts["+6 silent · English"].waitForExistence(timeout: 10))
        shot(app, "8-clock")
        app.buttons["Stop"].tap()
        XCTAssertTrue(app.staticTexts["Time's up!"].waitForExistence(timeout: 3))
        shot(app, "9-clock-over")
    }

    /// Multiplayer: players and rules first, then set, hand over, solve, see the points.
    @MainActor
    func testMultiplayer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoText", "", "-duel.players", "", "-meaning", "yes", "-duel.meaningBonus", "YES"]
        app.launch()
        app.buttons["Game"].tap()
        app.buttons["Multiplayer"].tap()
        app.buttons["Add player"].tap()
        for (i, name) in ["Ada", "Bo", "Cy"].enumerated() {
            let field = app.textFields.element(boundBy: i)
            field.tap()
            field.typeText(name)
        }
        app.buttons["1 min"].tap()
        app.buttons["One language"].tap()
        app.buttons["Letters"].tap()
        XCTAssertTrue(app.staticTexts["A point per letter of the sentence."].exists)
        shot(app, "10-multi-setup")
        app.swipeUp()
        app.buttons["Start"].tap()
        XCTAssertTrue(app.staticTexts["Ada: type a sentence for Bo, or read one with the camera."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Options"].exists)
        typeSentence(app, "Dormitory")
        tapMakeAnagram(app)
        XCTAssertTrue(app.staticTexts["Pass the phone to Bo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["9 letters, 1 minute to make an anagram."].exists)
        XCTAssertTrue(app.staticTexts["Meaning ×2"].exists)
        shot(app, "11-multi-handoff")
        app.buttons["I'm ready"].tap()
        XCTAssertFalse(app.buttons["Suggest"].exists)
        for letter in ["D", "I", "R", "T", "Y"] { app.staticTexts.matching(identifier: letter).firstMatch.tap() }
        app.buttons["Space"].tap()
        for letter in ["R", "O", "O", "M"] { app.staticTexts.matching(identifier: letter).firstMatch.tap() }
        shot(app, "12-multi-solving")
        app.buttons["Check"].tap()
        // letters scoring: 9, doubled because it means something
        XCTAssertTrue(app.staticTexts["Bo did it! +18"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["It makes sense: double points!"].exists)
        XCTAssertTrue(app.staticTexts["English"].exists)
        shot(app, "13-multi-result")
        XCTAssertTrue(app.buttons["Next: Bo writes a sentence"].exists)
    }

    /// A sentence from the app, a suggestion laid out, a free "!" added: it's an anagram.
    @MainActor
    func testGivenSentenceSuggestionAndPunctuation() throws {
        let app = launch(["-demoText", ""])
        app.buttons["Give me a sentence"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Easy'")).firstMatch.tap()
        shot(app, "14-given")
        tapMakeAnagram(app)
        app.buttons["Suggest"].tap()
        let first = app.cells.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        shot(app, "15-suggestions")
        first.buttons.firstMatch.exists ? first.buttons.firstMatch.tap() : first.tap()
        app.buttons["Add !"].tap()
        shot(app, "16-arranged")
        app.buttons["Check"].tap()
        XCTAssertTrue(app.staticTexts["Yes! It's an anagram."].waitForExistence(timeout: 10))
        shot(app, "17-verdict")
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        let training = app.buttons["Training"]
        XCTAssertTrue(training.waitForExistence(timeout: 5))
        training.tap()
        return app
    }

    @MainActor
    /// Types the sentence in the field (the games have no voice).
    private func typeSentence(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text + "\n")
    }

    private func tapMakeAnagram(_ app: XCUIApplication) {
        let make = app.buttons["Make anagram"]
        XCTAssertTrue(make.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: make)], timeout: 5)
        sleep(2)  // let the whole demo sentence arrive
        make.tap()
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["ANAGRAMS_SHOTS"] {
            try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
