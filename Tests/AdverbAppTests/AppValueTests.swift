import Foundation
import Testing
@testable import AdverbApp
import AdverbCore

@Suite struct AppValueTests {
    @Test func headlinesSplitThePayoff() {
        let parts = Headline.parts("Highlight *a line.*")
        #expect(parts.map(\.text) == ["Highlight ", "a line."])
        #expect(parts.map(\.payoff) == [false, true])
        #expect(Headline.parts("Plain").map(\.payoff) == [false])
        #expect(Headline.parts("*All gold*").map(\.payoff) == [true])
    }

    @Test func menuKeysAreUnique() {
        for items in [MainMenu.appItems, MainMenu.fileItems, MainMenu.campaignItems] {
            let keys = items.compactMap { $0.title == nil || $0.key.isEmpty ? nil : "\($0.key)|\($0.modifiers.rawValue)" }
            #expect(Set(keys).count == keys.count)
        }
    }

    @Test func languageChipsKeepTheirOrder() {
        #expect(LanguageChips.toggled(.french, in: [.spanish]) == [.french, .spanish])
        #expect(LanguageChips.toggled(.spanish, in: [.french, .spanish]) == [.french])
        #expect(LanguageChips.toggled(.japanese, in: []) == [.japanese])
    }

    @Test func quotaReadsPlainly() {
        let line = VoicePage.quotaLine(VoiceQuota(used: 12_340, limit: 100_000, tier: "creator"))
        #expect(line.hasPrefix("12,340 of 100,000 characters used this period"))
        #expect(line.hasSuffix("· Creator plan"))
        #expect(VoiceCard.modelTitle("eleven_multilingual_v2") == "Multilingual v2")
        #expect(VoiceCard.modelTitle("eleven_other") == "eleven_other")
    }

    @Test func settingsSectionsHaveCopy() {
        for s in SettingsSection.allCases {
            #expect(!s.title.isEmpty)
            #expect(!s.subtitle.isEmpty)
        }
    }
}
