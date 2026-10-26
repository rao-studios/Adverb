//
//  RowCard.swift
//  Adverb
//
//  WHAT: A list row: brightens under the pointer, a gold edge when selected.
//

import SwiftUI

struct RowCard<Content: View>: View {
    var selected = false
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        content
            .padding(.layer3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.adverbFillSelected : (hovering ? Color.adverbFillTrace : Color.adverbPearl))
            .clipShape(RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous)
                .strokeBorder(selected ? Color.adverbGold : Color.adverbBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous))
            .onHover { hovering = $0 }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
