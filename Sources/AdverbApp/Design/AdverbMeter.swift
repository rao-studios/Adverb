//
//  AdverbMeter.swift
//  Adverb
//
//  WHAT: A thin capsule filled to a fraction, in gold.
//

import SwiftUI

struct AdverbMeter: View {
    let fraction: Double
    var tint: Color = .adverbGold
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.adverbFill)
                Capsule().fill(tint).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityValue("\(Int((min(max(fraction, 0), 1) * 100).rounded())) percent")
    }
}
