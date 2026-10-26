//
//  AdverbStat.swift
//  Adverb
//
//  WHAT: A value over its label, for summary rows.
//

import SwiftUI

struct AdverbStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: .hairline) {
            Text(value).adverbType(.figure).foregroundStyle(Color.adverbInk)
            Text(label.uppercased()).adverbType(.badge).foregroundStyle(Color.adverbInkDim)
        }
        .lineLimit(1)
        .fixedSize()
    }
}
