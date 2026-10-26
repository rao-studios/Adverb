//
//  NewProjectSheet.swift
//  Adverb
//
//  WHAT: A new project: an existing folder Adverb reads for context (never writes), a name, a label,
//        tags, and the app identity its assets carry. Makes <workdir>/Adverb/<slug>/ with the kit.
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct NewProjectSheet: View {
    let selection: DeskSelection
    @State private var name = ""
    @State private var context: URL?
    @State private var label: ProjectLabel = .gold
    @State private var tags = ""
    @State private var identity = AppIdentity.ambient
    @State private var creating = false

    var body: some View {
        SheetFrame(kicker: "New project", title: "A folder you *already work in.*") {
            FormRow(label: "Context folder", hint: "Read for its README, docs and pages. Adverb never writes to it.") {
                HStack {
                    Button(context == nil ? "Choose…" : "Change…") {
                        if let url = Panels.chooseFolder(title: "Project folder", prompt: "Use as Context",
                                                         message: "Adverb reads this folder for context and never writes to it.", canCreate: false) {
                            context = url
                            if name.isEmpty { name = url.lastPathComponent }
                            if let preset = AppIdentity.presets.first(where: { $0.name.lowercased() == url.lastPathComponent.lowercased() }) { identity = preset }
                        }
                    }
                    .buttonStyle(.adverbQuiet)
                    Text(context?.path ?? "No folder yet").adverbType(.identifier).foregroundStyle(Color.adverbInkDim).lineLimit(1).truncationMode(.middle)
                }
            }
            HStack(spacing: .layer2) {
                FormRow(label: "Name") { AdverbTextField(placeholder: "Ambient", text: $name) }
                FormRow(label: "Label") {
                    Picker("", selection: $label) { ForEach(ProjectLabel.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                        .labelsHidden().fixedSize()
                }
            }
            FormRow(label: "Tags", hint: "Comma separated") { AdverbTextField(placeholder: "reader, mac", text: $tags) }
            IdentityEditor(identity: $identity)
        } actions: {
            Button("Cancel") { selection.sheet = nil }.buttonStyle(.adverbQuiet).keyboardShortcut(.cancelAction)
            if creating { ProgressView().controlSize(.small) }
            Button("Add project") {
                guard let context else { return }
                creating = true
                Task {
                    let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if let project = await AdverbRuntimeRoot.shared.createProject(name: name.trimmingCharacters(in: .whitespaces), context: context,
                                                                                    app: identity, label: label, tags: tagList) {
                        selection.select(project: project.slug)
                        selection.sheet = nil
                    }
                    creating = false
                }
            }
            .buttonStyle(.adverb).keyboardShortcut(.defaultAction)
            .disabled(context == nil || name.trimmingCharacters(in: .whitespaces).isEmpty || creating)
        }
    }
}
