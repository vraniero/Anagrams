import XCTest

/// Not a test: plays a short tour of the app for the App Store preview video, while the
/// simulator records (`xcrun simctl io <sim> recordVideo`). Writes when the tour starts and
/// ends, for trimming.
final class PreviewTourTests: XCTestCase {
    private var marks: [Double] = []

    private func mark() { marks.append(Date().timeIntervalSince1970) }

    private func tapLetters(_ app: XCUIApplication, _ letters: [String]) {
        for letter in letters {
            if letter == " " { app.buttons["Space"].tap() } else { app.staticTexts.matching(identifier: letter).firstMatch.tap() }
            usleep(180_000)
        }
    }

    private func makeAnagram(_ app: XCUIApplication) {
        let make = app.buttons["Make anagram"]
        XCTAssertTrue(make.waitForExistence(timeout: 15))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: make)], timeout: 15)
        usleep(600_000)
        make.tap()
        usleep(700_000)
    }

    @MainActor
    func testTour() throws {
        // only when recording the preview (TEST_RUNNER_ANAGRAMS_PREVIEW=<folder>)
        guard let dir = ProcessInfo.processInfo.environment["ANAGRAMS_PREVIEW"] else {
            throw XCTSkip("Records the App Store preview; set ANAGRAMS_PREVIEW to run it.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-demoText", "", "-meaning", "yes", "-grammar", "ok", "-givenSentence", "Listen",
                               "-onlineDemo", "-duel.sentencesBy", "players", "-duel.rounds", "1", "-mute"]
        app.launch()
        XCTAssertTrue(app.buttons["Training"].waitForExistence(timeout: 10))
        mark()
        sleep(2)

        // write a sentence, build its anagram, and it makes sense
        app.buttons["Training"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Dormitory\n")
        makeAnagram(app)
        tapLetters(app, ["D", "I", "R", "T", "Y", " ", "R", "O", "O", "M"])
        app.buttons["Check"].tap()
        XCTAssertTrue(app.staticTexts["It makes sense!"].waitForExistence(timeout: 10))
        sleep(2)
        app.buttons["Done"].tap()
        usleep(500_000)
        app.navigationBars.buttons.firstMatch.tap()

        // against the clock
        app.buttons["Game"].tap()
        app.buttons["Against the clock"].tap()
        app.buttons["Start"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "L").firstMatch.waitForExistence(timeout: 5))
        usleep(500_000)
        tapLetters(app, ["S", "I", "L", "E", "N", "T"])
        app.buttons["Check"].tap()
        XCTAssertTrue(app.staticTexts["+6 silent · English"].waitForExistence(timeout: 10))
        sleep(1)
        app.navigationBars.buttons.firstMatch.tap()

        // online: send a sentence, get one back
        app.buttons["Online"].tap()
        app.buttons["New game"].tap()
        let friend = app.buttons["Invite a friend"]
        for _ in 0..<4 where !friend.isHittable { app.swipeUp() }
        friend.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
        app.textFields.firstMatch.tap()
        app.textFields.firstMatch.typeText("Listen\n")
        makeAnagram(app)
        XCTAssertTrue(app.staticTexts["Robin sent you a sentence"].waitForExistence(timeout: 10))
        sleep(2)
        mark()

        try marks.map { String($0) }.joined(separator: "\n")
            .write(toFile: dir + "/tour-times.txt", atomically: true, encoding: .utf8)
    }
}
