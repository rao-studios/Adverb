//
//  NoticeBar.swift
//  Adverb
//
//  WHAT: The line along a window's foot: the last thing that happened, or what went wrong.
//        Selectable, so an error can be copied; dismissable.
//

import SwiftUI

struct NoticeBar: View {
    let text: String
    let tint: Color
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: .layer2) {
            Text(text)
                .adverbType(.caption).foregroundStyle(tint)
                .lineLimit(3).truncationMode(.tail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark").font(.adverbGlyph(AdverbGlyph.caption, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(Color.adverbInkMuted).help("Dismiss")
            }
        }
        .padding(.horizontal, .layer4)
        .padding(.vertical, .layer2)
        .background(Color.adverbPearlLow)
        .overlay(alignment: .top) { Rectangle().fill(Color.adverbBorder).frame(height: 1) }
    }
}
