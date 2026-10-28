//
//  LanguageChips.swift
//  Adverb
//
//  WHAT: The languages a voice-over can be made in, as chips to toggle. The choice is the saved
//        preference: whoever shows the chips persists the change it hands back.
//

import AdverbCore
import SwiftUI

struct LanguageChips: View {
    let selected: [Language]
    /// A check on the chip: that language's videos are already made.
    var mark: (Language) -> Bool = { _ in false }
    var disabled = false
    let change: ([Language]) -> Void

    /// `list` with `language` in or out, in the canonical order.
    static func toggled(_ language: Language, in list: [Language]) -> [Language] {
        list.contains(language) ? list.filter { $0 != language } : (list + [language]).sorted()
    }

    var body: some View {
        FlowLayout(spacing: .snug) {
            ForEach(Language.targets) { language in
                Button { change(Self.toggled(language, in: selected)) } label: {
                    AdverbChip(label: language.title, systemImage: mark(language) ? "checkmark" : nil, isOn: selected.contains(language))
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .help(language.nativeTitle)
            }
        }
    }
}
