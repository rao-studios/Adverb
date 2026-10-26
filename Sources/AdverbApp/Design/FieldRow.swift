//
//  FieldRow.swift
//  Adverb
//
//  WHAT: A label and its value on one line; the value truncates in the middle and is whole in its
//        tooltip, and selectable.
//

import SwiftUI

struct FieldRow: View {
    let label: String
    let value: String
    var mono = true
    var labelWidth: CGFloat = 120

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: .layer3) {
            Text(label).adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                .lineLimit(1).frame(width: labelWidth, alignment: .leading)
            Text(value).adverbType(mono ? .identifier : .caption).foregroundStyle(Color.adverbInkSoft)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(value)
        }
    }
}
