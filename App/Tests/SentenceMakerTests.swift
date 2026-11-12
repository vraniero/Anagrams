import Foundation
import Testing
@testable import Anagrams

@MainActor
struct SentenceMakerTests {
    @Test func readsTitlesAndDatesFromRSS() {
        let rss = """
            <rss><channel><title>Top stories</title>
            <item><title>Il sole è tornato - ANSA</title><pubDate>Sat, 07 Nov 2026 10:00:00 GMT</pubDate></item>
            <item><title>Hacker russi, dati sul web - Il Sole 24 ORE</title><pubDate>Fri, 06 Nov 2026 08:30:00 GMT</pubDate></item>
            </channel></rss>
            """
        let items = RSSTitles.parse(Data(rss.utf8))
        #expect(items.map(\.title) == ["Il sole è tornato - ANSA", "Hacker russi, dati sul web - Il Sole 24 ORE"])
        #expect(items.allSatisfy { $0.date != nil })
        #expect(NewsHeadlines.withoutSource(items[1].title) == "Hacker russi, dati sul web")
    }

    @Test func headlinesGiveClausesAndWords() {
        let parts = SentenceMaker.parts(of: "Midterm, Trump ordina indagini: “Minacciano molte persone”")
        #expect(parts.contains("Midterm"))
        #expect(parts.contains("Trump ordina indagini"))
        #expect(parts.contains("Minacciano molte persone"))
        // one word: not names
        #expect(SentenceMaker.words(of: "Trump ordina indagini", language: "it") == ["ordina", "indagini"])
        #expect(SentenceMaker.letters(.medium).contains(SentenceMaker.letterCount("Hacker russi")))
    }

    @Test func sentencesStayWithinTheLetterLimit() {
        #expect(SentenceMaker.letters(.hard, maxLetters: 15) == 12...15)
        #expect(SentenceMaker.letters(.hard, maxLetters: 10) == 10...10)
        #expect(SentenceMaker.letters(.medium, maxLetters: nil) == SentenceMaker.letters(.medium))
        for _ in 0..<30 {
            let sentence = SentenceBank.random(.hard, language: "en", maxLetters: 12)
            #expect(sentence.map { SentenceMaker.letterCount($0.text) <= 12 } ?? false)
        }
    }

    @Test func givenSentencesNeverRepeat() {
        SentenceHistory.forget()
        defer { SentenceHistory.forget() }
        var given: [String] = []
        while let sentence = SentenceBank.random(.hard, language: "en", fresh: true) {
            given.append(SentenceHistory.fold(sentence.text))
            SentenceHistory.remember(sentence.text)
        }
        #expect(!given.isEmpty)
        #expect(Set(given).count == given.count)
        // all given: the one given longest ago comes back
        #expect(SentenceBank.random(.hard, language: "en", fresh: false).map { SentenceHistory.fold($0.text) } == given.first)
        #expect(SentenceHistory.wasGiven(given[0].uppercased() + "!"))
    }

    @Test func literatureGivesRealLinesWithTheirAuthor() async {
        SentenceHistory.forget()
        defer { SentenceHistory.forget() }
        let languages = Set(Literature.all.map(\.lang))
        #expect(languages.isSuperset(of: Set(SentenceBank.all.map(\.lang))))
        #expect(Literature.all.allSatisfy { !$0.author.isEmpty && !$0.work.isEmpty })
        #expect(Set(Literature.all.map(\.text)).count == Literature.all.count)
        for language in languages {
            #expect(Literature.all.filter { $0.lang == language }.count >= 80, "\(language)")
        }
        for level in SentenceBank.Level.allCases {
            for language in languages.sorted() {
                let made = await SentenceMaker.make(level, source: .literature, language: language)
                let quote = try? #require(made?.quote, "\(level) \(language)")
                #expect(quote?.lang == language)
                #expect(made.map { SentenceMaker.letters(level).contains(SentenceMaker.letterCount($0.text)) } == true)
                // a piece of the real line
                #expect(made.map { quote?.text.contains($0.text) == true } == true)
            }
        }
    }
}
