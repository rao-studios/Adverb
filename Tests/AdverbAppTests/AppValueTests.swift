import Foundation
import Testing
@testable import AdverbApp

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

    @Test func settingsSectionsHaveCopy() {
        for s in SettingsSection.allCases {
            #expect(!s.title.isEmpty)
            #expect(!s.subtitle.isEmpty)
        }
    }
}
