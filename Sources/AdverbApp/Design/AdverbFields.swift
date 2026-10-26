//
//  AdverbFields.swift
//  Adverb
//
//  WHAT: The one-line fields, in pearl chrome: plain, secret (the API key), and multi-line.
//

import AppKit
import SwiftUI

struct AdverbTextField: View {
    let placeholder: String
    @Binding var text: String
    var role: AdverbType = .label

    var body: some View {
        TextField(placeholder, text: $text).textFieldStyle(.plain).adverbType(role).adverbFieldChrome()
    }
}

struct AdverbSecureField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        SecureField(placeholder, text: $text).textFieldStyle(.plain).adverbType(.identifier).adverbFieldChrome()
    }
}

struct AdverbTextArea: View {
    @Binding var text: String
    var role: AdverbType = .readingSmall
    var minHeight: CGFloat = 72

    var body: some View {
        TextEditor(text: $text)
            .adverbType(role)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .padding(.layer1)
            .background(Color.adverbPearl, in: RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous).strokeBorder(Color.adverbBorder))
    }
}
