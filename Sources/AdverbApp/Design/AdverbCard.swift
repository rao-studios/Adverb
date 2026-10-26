//
//  AdverbCard.swift
//  Adverb
//
//  WHAT: The one raised surface: pearl inside a hairline, a soft shadow (the skill's .card).
//

import SwiftUI

struct AdverbCard<Content: View>: View {
    var padding: CGFloat = .layer4
    var gold = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AdverbRadius.card, style: .continuous)
                    .fill(LinearGradient(colors: [.adverbPearl, .adverbPearlLow], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: AdverbRadius.card, style: .continuous)
                        .strokeBorder(gold ? Color.adverbGold.opacity(0.55) : Color.adverbBorder, lineWidth: gold ? 1.5 : 1)))
            .shadow(color: Color.adverbShadow, radius: 10, y: 4)
    }
}
