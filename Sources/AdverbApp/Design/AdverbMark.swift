//
//  AdverbMark.swift
//  Adverb
//
//  WHAT: The app's mark, as the icon draws it: an italic gold "ly" over a brushstroke.
//

import SwiftUI

struct AdverbMark: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.adverbBrush)
                .frame(width: size * 0.95, height: size * 0.2)
                .rotationEffect(.degrees(-2))
                .offset(y: size * 0.12)
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
