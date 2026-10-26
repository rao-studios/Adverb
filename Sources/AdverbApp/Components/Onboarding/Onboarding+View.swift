//
//  Onboarding+View.swift
//  Adverb
//

import AdverbCore
import AdverbRuntime
import SwiftUI

extension Onboarding {
    var view: some View {
        let state = config.state
        return VStack(spacing: 0) {
            Spacer(minLength: .layer5)
            VStack(alignment: .leading, spacing: .layer5) {
                HStack(alignment: .center, spacing: .layer3) {
                    AdverbMark(size: 44)
                    VStack(alignment: .leading, spacing: .hairline) {
                        Kicker(text: "Rao Studios · Adverb")
                        Headline(text: "A month of motion, *planned.*", role: .pageTitle)
                    }
                }
                steps
                AdverbCard {
                    switch step {
                    case .key: keyStep(state)
                    case .workdir: workdirStep(state)
                    case .project: projectStep
                    }
                }
                if let problem = state.problem {
                    Text(problem).adverbType(.caption).foregroundStyle(Color.adverbError).textSelection(.enabled)
                } else if let notice = state.notice {
                    Text(notice).adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                }
            }
            .frame(width: AdverbLayout.onboardingWidth)
            Spacer(minLength: .layer5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(configChanged) { _ in tick &+= 1 }
    }

    private var steps: some View {
        HStack(spacing: .layer3) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                HStack(spacing: .snug) {
                    ZStack {
                        Circle().fill(s.rawValue < step.rawValue ? Color.adverbGold : (s == step ? Color.adverbInk : Color.adverbFill))
                            .frame(width: 18, height: 18)
                        if s.rawValue < step.rawValue {
                            Image(systemName: "checkmark").font(.adverbGlyph(AdverbGlyph.small, weight: .bold)).foregroundStyle(Color.adverbPearl)
                        } else {
                            Text("\(s.rawValue + 1)").adverbType(.badge).foregroundStyle(s == step ? Color.adverbPearl : Color.adverbInkDim)
                        }
                    }
                    Text(s.title).adverbType(s == step ? .labelStrong : .label).foregroundStyle(s == step ? Color.adverbInk : Color.adverbInkDim)
                }
                if s != Step.allCases.last { Rectangle().fill(Color.adverbBorder).frame(width: 24, height: 1) }
            }
        }
    }

    @ViewBuilder private func keyStep(_ state: ConfigService.Center.State) -> some View {
        VStack(alignment: .leading, spacing: .layer3) {
            Text("Adverb plans each month and writes each asset with Claude, using the rao-motion-assets skill. It needs your Claude API key.")
                .adverbType(.reading).foregroundStyle(Color.adverbInkSoft)
            AdverbSecureField(placeholder: "sk-ant-…", text: $form.key)
                .onSubmit(saveKey)
            Text("Saved in your login Keychain (service nyc.rao.adverb). Never written to a file, never shown again in full. ANTHROPIC_API_KEY in the environment works too.")
                .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
            HStack {
                Spacer()
                if form.saving { ProgressView().controlSize(.small) }
                Button("Save key", action: saveKey).buttonStyle(.adverb).keyboardShortcut(.defaultAction)
                    .disabled(form.key.trimmingCharacters(in: .whitespaces).isEmpty || form.saving)
            }
        }
    }

    private func saveKey() {
        let key = form.key
        form.saving = true
        Task {
            if await AdverbRuntimeRoot.shared.saveKey(key) { form.key = "" }
            form.saving = false
        }
    }

    @ViewBuilder private func workdirStep(_ state: ConfigService.Center.State) -> some View {
        VStack(alignment: .leading, spacing: .layer3) {
            Text("Choose the folder Adverb works in. It makes an Adverb folder there, with one folder per project for its assets, captions and campaigns. Your projects themselves stay where they are: Adverb only reads them.")
                .adverbType(.reading).foregroundStyle(Color.adverbInkSoft)
            if FileManager.default.fileExists(atPath: "/Volumes/T9") {
                FieldRow(label: "Suggested", value: "/Volumes/T9 (your T9)")
            }
            HStack {
                if state.keySource != nil {
                    Label(state.keyMasked ?? "Key saved", systemImage: "key").adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                }
                Spacer()
                Button("Choose folder…") {
                    let start = FileManager.default.fileExists(atPath: "/Volumes/T9") ? URL(fileURLWithPath: "/Volumes/T9") : nil
                    if let url = Panels.chooseFolder(title: "Working directory", prompt: "Use This Folder",
                                                     message: "Adverb makes an Adverb folder here and keeps every project in it.", start: start) {
                        Task { await AdverbRuntimeRoot.shared.chooseWorkdir(url) }
                    }
                }
                .buttonStyle(.adverb).keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder private var projectStep: some View {
        VStack(alignment: .leading, spacing: .layer3) {
            Text("A project is a folder you already work in — an app's repository, a site — that Adverb reads for context: its README, its docs, its pages. Adverb never changes it.")
                .adverbType(.reading).foregroundStyle(Color.adverbInkSoft)
            HStack(spacing: .layer2) {
                Button(form.context == nil ? "Choose the project's folder…" : "Change folder…") {
                    if let url = Panels.chooseFolder(title: "Project folder", prompt: "Use as Context",
                                                     message: "Adverb reads this folder for context and never writes to it.", canCreate: false) {
                        form.context = url
                        if form.projectName.isEmpty { form.projectName = url.lastPathComponent }
                        if let preset = AppIdentity.presets.first(where: { $0.name.lowercased() == url.lastPathComponent.lowercased() }) { form.preset = preset.name }
                    }
                }.buttonStyle(.adverbQuiet)
                if let context = form.context { Text(context.path).adverbType(.identifier).foregroundStyle(Color.adverbInkDim).lineLimit(1).truncationMode(.middle) }
            }
            AdverbTextField(placeholder: "Name", text: $form.projectName)
            Picker("App", selection: $form.preset) {
                ForEach(AppIdentity.presets, id: \.name) { Text($0.name).tag($0.name) }
                Text("Another app").tag("custom")
            }
            .pickerStyle(.segmented)
            HStack {
                Spacer()
                if form.creating { ProgressView().controlSize(.small) }
                Button("Add project") {
                    guard let context = form.context else { return }
                    let name = form.projectName.trimmingCharacters(in: .whitespaces)
                    let identity = AppIdentity.presets.first { $0.name == form.preset } ?? .custom(name)
                    form.creating = true
                    Task {
                        if let project = await AdverbRuntimeRoot.shared.createProject(name: name, context: context, app: identity, label: .gold, tags: []) {
                            selection.select(project: project.slug)
                            selection.sheet = .newCampaign(project.slug)
                        }
                        form.creating = false
                    }
                }
                .buttonStyle(.adverb).keyboardShortcut(.defaultAction)
                .disabled(form.context == nil || form.projectName.trimmingCharacters(in: .whitespaces).isEmpty || form.creating)
            }
        }
    }
}
