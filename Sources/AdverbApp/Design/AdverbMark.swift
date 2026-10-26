//
//  AdverbMark.swift
//  Adverb
//
//  WHAT: The app's mark, as the icon draws it: an italic gold "ly", highlighted across its x-height.
//

import SwiftUI

struct AdverbMark: View {
    var size: CGFloat = 56

    var body: some View {
        // The highlight stands on the text's baseline and reaches just under the tops of the y's
        // arms: a little under Instrument Serif's x-height (346 px at 660 px type on the icon).
        ZStack(alignment: Alignment(horizontal: .center, vertical: .firstTextBaseline)) {
            RoundedRectangle(cornerRadius: AdverbRadius.hairline)
                .fill(Color.adverbBrush)
                .frame(width: size * 0.95, height: size * 0.46)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }
            Text("ly")
                .font(.adverbDisplay(size, italic: true))
                .foregroundStyle(LinearGradient(colors: [.adverbGoldLight, .adverbGold, .adverbGoldDeep],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .frame(width: size * 1.1, height: size * 1.1)
        .accessibilityLabel("Adverb")
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    var mark = true

    var body: some View {
        VStack(spacing: .layer3) {
            if mark { AdverbMark(size: 48) }
            Headline(text: title, role: .title).multilineTextAlignment(.center)
            Text(message).adverbType(.readingSmall).foregroundStyle(Color.adverbInkDim)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .padding(.layer6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
