//
//  AdverbChip.swift
//  Adverb
//
//  WHAT: A one-line chip (the skill's .chip): mono uppercase, a gold swatch when it is a source.
//

import SwiftUI

struct AdverbChip: View {
    let label: String
    var systemImage: String?
    var isOn = false
    var swatch = false
    var maxWidth: CGFloat?

    var body: some View {
        HStack(spacing: .layer1) {
            if swatch { RoundedRectangle(cornerRadius: AdverbRadius.hairline).fill(Color.adverbBrush).frame(width: 14, height: 7) }
            if let systemImage { Image(systemName: systemImage).font(.adverbGlyph(AdverbGlyph.small, weight: .semibold)) }
            Text(label.uppercased()).adverbType(.badge)
                .truncationMode(.middle)
                .frame(maxWidth: maxWidth, alignment: .leading)
        }
        .lineLimit(1)
        .fixedSize(horizontal: maxWidth == nil, vertical: true)
        .foregroundStyle(isOn ? Color.adverbPearl : Color.adverbInkDim)
        .padding(AdverbInset.chip)
        .background(RoundedRectangle(cornerRadius: AdverbRadius.chip, style: .continuous)
            .fill(isOn ? Color.adverbInk : Color.white.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: AdverbRadius.chip, style: .continuous).strokeBorder(isOn ? Color.clear : Color.adverbBorder))
    }
}
