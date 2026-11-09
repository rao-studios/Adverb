//
//  ModelsFolderField.swift
//  Adverb
//
//  WHAT: The folder models are kept in and looked for: a path to type (prefilled ~/.rao/models), a
//        folder to choose, and the way back to the default. Applied on Return or a choice: the app
//        searches it again and shows what it found.
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct ModelsFolderField: View {
    /// The setting as saved (nil: the default).
    let saved: String?
    @State private var text = ""

    private var current: String { saved ?? ModelHome.display(ModelHome.defaultRoot()) }

    var body: some View {
        VStack(alignment: .leading, spacing: .snug) {
            HStack(spacing: .layer2) {
                AdverbTextField(placeholder: ModelHome.display(ModelHome.defaultRoot()), text: $text, role: .identifier)
                    .onSubmit { apply(ModelHome.url(text.isEmpty ? current : text)) }
                Button("Choose…") {
                    if let url = Panels.chooseFolder(title: "Models folder", prompt: "Use",
                                                     message: "Choose the folder Adverb keeps its models in and looks through for models Rao apps already downloaded.",
                                                     start: ModelHome.url(current)) {
                        text = ModelHome.display(url)
                        apply(url)
                    }
                }
                .buttonStyle(.adverbQuiet)
            }
            HStack(spacing: .layer2) {
                if text != current {
                    Button("Use this folder") { apply(ModelHome.url(text)) }.buttonStyle(.adverbLink)
                }
                if saved != nil {
                    Button("Use \(ModelHome.display(ModelHome.defaultRoot()))") {
                        text = ModelHome.display(ModelHome.defaultRoot())
                        apply(nil)
                    }
                    .buttonStyle(.adverbLink)
                }
            }
        }
        .onAppear { text = current }
        .onChange(of: saved) { _, _ in text = current }
    }

    private func apply(_ folder: URL?) {
        Task { await AdverbRuntimeRoot.shared.useModelsFolder(folder) }
    }
}
