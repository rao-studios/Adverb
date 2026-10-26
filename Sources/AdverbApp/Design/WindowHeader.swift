//
//  WindowHeader.swift
//  Adverb
//
//  WHAT: The bar across the top of a pane: a kicker, a title, and the pane's actions.
//

import SwiftUI

struct WindowHeader<Actions: View>: View {
    let kicker: String
    let title: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: .layer3) {
            VStack(alignment: .leading, spacing: .hairline) {
                Kicker(text: kicker)
                Headline(text: title, role: .pageTitle).lineLimit(1)
            }
            Spacer(minLength: .layer3)
            actions
        }
        .padding(.horizontal, .layer5)
        .padding(.top, .layer4)
        .padding(.bottom, .layer3)
    }
}
