//
//  ManageProjectSheet.swift
//  Adverb
//
//  WHAT: A project's name, label, tags, notes and identity; and removing it from Adverb. Removal asks
//        first, offers to keep the project's Adverb folder (its assets and campaigns), and never
//        touches the context folder.
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct ManageProjectSheet: View {
    let slug: String
    let selection: DeskSelection
    @State private var project: Project?
    @State private var tags = ""
    @State private var confirming = false
    @State private var deleteFolder = false
    @State private var size: Int64 = 0

    var body: some View {
        Group {
            if let binding = Binding($project) {
                SheetFrame(kicker: "Manage project", title: binding.wrappedValue.name) {
                    HStack(spacing: .layer2) {
                        FormRow(label: "Name") { AdverbTextField(placeholder: "Name", text: binding.name) }
                        FormRow(label: "Label") {
                            Picker("", selection: binding.label) { ForEach(ProjectLabel.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                                .labelsHidden().fixedSize()
                        }
                    }
                    FormRow(label: "Tags", hint: "Comma separated") { AdverbTextField(placeholder: "reader, mac", text: $tags) }
                    FormRow(label: "Notes") { AdverbTextArea(text: binding.notes, minHeight: 60) }
                    FormRow(label: "Context folder") {
                        FieldRow(label: "Reads", value: binding.wrappedValue.contextPath)
                        Button("Point at another folder…") {
                            if let url = Panels.chooseFolder(title: "Project folder", prompt: "Use as Context", message: "Adverb reads this folder and never writes to it.", canCreate: false) {
                                binding.wrappedValue.contextPath = url.standardizedFileURL.path
                            }
                        }.buttonStyle(.adverbLink)
                    }
                    IdentityEditor(identity: binding.app)
                    AdverbCard {
                        VStack(alignment: .leading, spacing: .layer2) {
                            SectionLabel("Remove from Adverb", color: .adverbError)
                            Text("Removes \(binding.wrappedValue.name) from Adverb. \(binding.wrappedValue.contextPath) is never touched.")
                                .adverbType(.readingSmall).foregroundStyle(Color.adverbInkDim)
                            Toggle("Also delete its Adverb folder: every campaign, video and caption file (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))",
                                   isOn: $deleteFolder).adverbType(.label)
                            Button("Remove…") { confirming = true }.buttonStyle(.adverbDestructive)
                        }
                    }
                } actions: {
                    Button("Cancel") { selection.sheet = nil }.buttonStyle(.adverbQuiet).keyboardShortcut(.cancelAction)
                    Button("Save") {
                        var p = binding.wrappedValue
                        p.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        Task { await AdverbRuntimeRoot.shared.saveProject(p); selection.sheet = nil }
                    }
                    .buttonStyle(.adverb).keyboardShortcut(.defaultAction)
                }
                .confirmationDialog(deleteFolder ? "Remove \(binding.wrappedValue.name) and delete its Adverb folder?" : "Remove \(binding.wrappedValue.name) from Adverb?",
                                    isPresented: $confirming, titleVisibility: .visible) {
                    Button(deleteFolder ? "Remove and delete the folder" : "Remove, keep the folder", role: .destructive) {
                        let p = binding.wrappedValue
                        selection.sheet = nil
                        selection.select(project: nil)
                        Task { await AdverbRuntimeRoot.shared.removeProject(p, deleteFolder: deleteFolder) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(deleteFolder ? "Its campaigns and assets are deleted from the drive. The context folder stays as it is."
                                      : "Its Adverb folder is set aside (renamed .removed-…) with every asset in it. The context folder stays as it is.")
                }
            } else {
                ProgressView().frame(width: AdverbLayout.sheetWidth, height: 200)
            }
        }
        .task {
            let p = AdverbRuntimeRoot.shared.projects.state.project(slug)
            project = p
            tags = p?.tags.joined(separator: ", ") ?? ""
            if let p { size = await AdverbRuntimeRoot.shared.folderSize(p) }
        }
    }
}
