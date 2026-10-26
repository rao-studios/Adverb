//
//  Headline.swift
//  Adverb
//
//  WHAT: A headline as the skill writes them: "Highlight *a line.*" — the plain clause in ink, the
//        payoff in italic gold. Also the kicker: a gold coin and a mono label.
//

import SwiftUI

struct Headline: View {
    let text: String
    var role: AdverbType = .title

    var body: some View {
        Self.parts(text).reduce(Text("")) { result, part in
            let run = Text(part.text).font(.adverbDisplay(role.spec.size, italic: part.payoff)).kerning(role.kerning)
            return result + (part.payoff ? run.foregroundStyle(Color.adverbGold) : run.foregroundStyle(Color.adverbInk))
        }
    }

    /// "a *b* c" → [(a, plain), (b, payoff), (c, plain)].
    static func parts(_ text: String) -> [(text: String, payoff: Bool)] {
        var out: [(String, Bool)] = []
        var payoff = false
        for (i, piece) in text.components(separatedBy: "*").enumerated() {
            if i > 0 { payoff.toggle() }
            if !piece.isEmpty { out.append((piece, payoff)) }
        }
        return out
    }
}

struct Kicker: View {
    let text: String

    var body: some View {
        HStack(spacing: .snug) {
            Circle()
                .fill(RadialGradient(colors: [.adverbCoinHi, .adverbGold, .adverbGoldDeep],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 7))
                .frame(width: 10, height: 10)
            Text(text.uppercased()).adverbType(.section).foregroundStyle(Color.adverbInk).lineLimit(1)
        }
    }
}
