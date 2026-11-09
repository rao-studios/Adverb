//
//  ModelsPage.swift
//  Adverb
//
//  WHAT: Settings › Models: the writer (plans, pages, voice-overs, translations) and the eyes (the
//        contact sheet's review), each a model on this Mac, downloaded from Rao Studios; how the
//        writer works (thinking first, the review, the sheet gate, days at a time); and the skill.
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct ModelsPage: View {
    let state: ConfigService.Center.State
    let models: ModelService.Center.State
    var root: AdverbRuntimeRoot { AdverbRuntimeRoot.shared }

    var body: some View {
        let textID = state.settings.textModelID
        let writer = ModelCatalog.spec(textID)
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("The writer")
                Text("Plans the month, writes each page, its voice-over and its translations. Offered by this Mac's memory (\(models.memoryGB) GB); a larger one writes better and slower.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                if writer == nil {
                    FieldRow(label: "In use", value: textID)
                }
                ForEach(ModelCatalog.text.filter { $0.fits(memoryGB: models.memoryGB) || $0.id == textID || models.isInstalled($0.id) }, id: \.id) { spec in
                    ModelRow(spec: spec, state: models, inUse: spec.id == textID, canUse: true, canRemove: spec.id != textID,
                             onUse: { root.useTextModel(spec.id) })
                }
            }
        }
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("The eyes")
                if writer?.acceptsImages == true || root.writerReadsImages {
                    Text("\(writer?.title ?? ModelInfo.shortName(textID)) reads images: it looks at each contact sheet itself. A second model is needed only for a writer that cannot.")
                        .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                } else {
                    Text("This writer cannot read images: the eyes look at each contact sheet and the writer fixes what they find.")
                        .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                    ForEach(ModelCatalog.vision, id: \.id) { spec in
                        ModelRow(spec: spec, state: models, inUse: spec.id == (state.settings.visionModel ?? ModelCatalog.vision.first?.id),
                                 canUse: true, canRemove: true, onUse: { root.useVisionModel(spec.id) })
                    }
                }
            }
        }
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer3) {
                SectionLabel("How it works")
                Toggle("Let the writer think before it plans and writes a page", isOn: binding(\.thinking))
                Text("Slower, usually better pages. It thinks for at most \(state.settings.thinkingBudget.formatted()) tokens, then writes.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                Toggle("Look at each contact sheet and fix what is off", isOn: binding(\.reviewPass))
                Toggle("Stop each day at its contact sheet until I approve it", isOn: binding(\.sheetGate))
                Text(state.settings.sheetGate
                     ? "Each day is written to its sheet (page, voice, stills) and waits. Approve it, or send it back with a note; then render the approved days."
                     : "A day whose sheet passes its checks renders right away. Redo still works on any day.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                Stepper("Write \(state.settings.buildConcurrency) days at a time", value: binding(\.buildConcurrency), in: 1...2)
                Text("The writer takes one day at a time on the GPU; two lets the next day's stills and sheet overlap the writing.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
            .adverbType(.label)
        }
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("The skill")
                FieldRow(label: "Using", value: state.settings.skillPath ?? "The copy built into Adverb (rao-motion-assets)")
                HStack {
                    Button("Use a SKILL.md…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
                        panel.directoryURL = URL(fileURLWithPath: "/Volumes/T9/rao/marketing/rao-motion-assets")
                        if panel.runModal() == .OK, let url = panel.url { root.update { $0.skillPath = url.path } }
                    }.buttonStyle(.adverbQuiet)
                    if state.settings.skillPath != nil { Button("Use the built-in copy") { root.update { $0.skillPath = nil } }.buttonStyle(.adverbLink) }
                }
                Text("The skill is the writer's system prompt for every plan and every page. Point at the T9's copy while you edit it.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            }
        }
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("Where models are kept")
                ModelsFolderField(saved: state.settings.modelsFolder)
                Text(state.settings.modelsFolder == nil
                     ? "Adverb looks through this folder for models any Rao app has already downloaded, at any path, and uses them where they sit. A mirror's upstream counts when its bytes are the same. What is missing downloads here."
                     : "Adverb looks through this folder, and ~/.rao/models, for models any Rao app has already downloaded, and uses them where they sit. What is missing downloads here.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                FieldRow(label: "In use", value: ModelRow.size(models.totalBytes) + " for the models above")
                Button("Look again") { Task { await root.refreshModels() } }.buttonStyle(.adverbLink)
            }
        }
        .task { await root.refreshModels() }
    }

    private func binding<T>(_ path: WritableKeyPath<AdverbSettings, T>) -> Binding<T> {
        Binding(get: { state.settings[keyPath: path] }, set: { value in root.update { $0[keyPath: path] = value } })
    }
}
