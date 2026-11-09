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

    @MainActor @Test func voicePacksReadByName() {
        #expect(VoiceCard.packTitle(ModelCatalog.paradeePackID) == ModelCatalog.paradee.title)
        #expect(VoiceCard.packTitle("") == "Recorded before this Mac's voice")
        #expect(VoiceCard.packTitle("dev:somewhere") == "dev:somewhere")
    }

    @Test func arcPhasesSplitIntoTitleDatesAndDetail() {
        let phase = PlanSummary.Phase("Premise (Nov 4–7): what Ambient is. Notes in the margin of everything.")
        #expect(phase == PlanSummary.Phase(title: "Premise", when: "Nov 4–7", detail: "What Ambient is. Notes in the margin of everything."))
        #expect(PlanSummary.Phase("Launch week: the app") == PlanSummary.Phase(title: "Launch week", when: nil, detail: "The app"))
        #expect(PlanSummary.Phase("No colon here") == PlanSummary.Phase(title: "No colon here", when: nil, detail: ""))
        let long = "A phase written as one long sentence with no title at all: it keeps going"
        #expect(PlanSummary.Phase(long).title == long)
    }

    @Test func settingsSectionsHaveCopy() {
        for s in SettingsSection.allCases {
            #expect(!s.title.isEmpty)
            #expect(!s.subtitle.isEmpty)
        }
    }
}
