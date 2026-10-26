//
//  SectionLabel.swift
//  Adverb
//
//  WHAT: The mono uppercase section label (the skill's kicker style).
//

import SwiftUI

struct SectionLabel: View {
    let text: String
    var color: Color = .adverbInkMuted
    init(_ text: String, color: Color = .adverbInkMuted) { self.text = text; self.color = color }

    var body: some View {
        Text(text.uppercased()).adverbType(.section).foregroundStyle(color).lineLimit(1)
    }
}
