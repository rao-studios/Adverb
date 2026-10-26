//
//  AdverbBadge.swift
//  Adverb
//
//  WHAT: An uppercase capsule tag: DRAFT, LIVE, ARCHIVED, ♪.
//

import SwiftUI

struct AdverbBadge: View {
    let text: String
    var color: Color = .adverbInkDim
    var filled = false

    var body: some View {
        Text(text.uppercased())
            .adverbType(.badge)
            .foregroundStyle(filled ? Color.adverbPearl : color)
            .lineLimit(1)
            .fixedSize()
            .padding(AdverbInset.badge)
            .background(Capsule().fill(filled ? color : Color.clear))
            .overlay(Capsule().strokeBorder(color.opacity(filled ? 0 : 0.5), lineWidth: 1))
    }
}
