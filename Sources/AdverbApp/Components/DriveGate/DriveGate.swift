//
//  DriveGate.swift
//  Adverb
//
//  WHAT: The working directory's drive is not here: say so, offer to look again or choose another.
//        Adverb writes nothing meanwhile (Veil's rule).
//

import AdverbRuntime
import SwiftUI

struct DriveGate: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: .layer4) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.adverbGlyph(AdverbGlyph.display, weight: .light))
                .foregroundStyle(Color.adverbGold)
            Headline(text: title, role: .display).multilineTextAlignment(.center)
            Text(message).adverbType(.reading).foregroundStyle(Color.adverbInkDim).multilineTextAlignment(.center).frame(maxWidth: 440)
            HStack(spacing: .layer2) {
                Button("Look again") { Task { await AdverbRuntimeRoot.shared.refresh() } }.buttonStyle(.adverb)
                    .keyboardShortcut(.defaultAction)
                Button("Choose another folder…") {
                    if let url = Panels.chooseFolder(title: "Working directory", prompt: "Use This Folder",
                                                     message: "Adverb makes an Adverb folder here and keeps every project in it.") {
                        Task { await AdverbRuntimeRoot.shared.chooseWorkdir(url) }
                    }
                }.buttonStyle(.adverbQuiet)
            }
        }
        .padding(.layer7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
