//
//  SheetFrame.swift
//  Adverb
//
//  WHAT: A sheet's frame: a kicker and title, the body scrolling, the actions at the foot.
//

import SwiftUI

struct SheetFrame<Content: View, Actions: View>: View {
    let kicker: String
    let title: String
    var width: CGFloat = AdverbLayout.sheetWidth
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: .hairline) {
                Kicker(text: kicker)
                Headline(text: title, role: .title)
            }
            .padding(.layer5)
            ScrollView {
                VStack(alignment: .leading, spacing: .layer4) { content }
                    .padding(.horizontal, .layer5)
                    .padding(.bottom, .layer4)
            }
            Rectangle().fill(Color.adverbBorder).frame(height: 1)
            HStack(spacing: .layer2) {
                Spacer()
                actions
            }
            .padding(.layer4)
        }
        .frame(width: width)
        .frame(minHeight: 360, idealHeight: 620, maxHeight: 760)
        .background(Color.adverbPage)
    }
}

struct FormRow<Content: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: .layer1) {
            SectionLabel(label)
            content
            if let hint { Text(hint).adverbType(.fine).foregroundStyle(Color.adverbInkMuted) }
        }
    }
}
