//
//  View+Adverb.swift
//  Adverb
//
//  WHAT: The roots and the type modifier: light-locked platinum, gold tint.
//

import SwiftUI

extension View {
    func adverbType(_ role: AdverbType) -> some View {
        font(role.font).kerning(role.kerning).lineSpacing(role.lineSpacing)
    }

    /// The page surface. Apply once at a window's root.
    func adverbRoot() -> some View {
        self
            .tint(.adverbGold)
            .foregroundStyle(Color.adverbInk)
            .background(Color.adverbPage)
            .preferredColorScheme(.light)
    }

    func adverbSidebarRoot() -> some View {
        self
            .tint(.adverbGold)
            .foregroundStyle(Color.adverbInk)
            .scrollContentBackground(.hidden)
            .background(Color.adverbSidebar)
            .preferredColorScheme(.light)
    }

    /// A one-line field's chrome: pearl inside a hairline.
    func adverbFieldChrome() -> some View {
        padding(EdgeInsets(top: AdverbInset.control.top, leading: .layer2, bottom: AdverbInset.control.bottom, trailing: .layer2))
            .background(Color.adverbPearl, in: RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous).strokeBorder(Color.adverbBorder))
    }
}

extension Text {
    func adverbRun(_ role: AdverbType) -> Text { font(role.font).kerning(role.kerning) }
}
