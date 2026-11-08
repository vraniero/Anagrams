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
}
