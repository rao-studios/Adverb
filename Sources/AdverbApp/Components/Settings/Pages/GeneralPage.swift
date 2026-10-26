//
//  GeneralPage.swift
//  Adverb
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct GeneralPage: View {
    let state: ConfigService.Center.State
    var root: AdverbRuntimeRoot { AdverbRuntimeRoot.shared }

    var body: some View {
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("Working directory")
                FieldRow(label: "Folder", value: state.settings.workdir ?? "Not chosen")
                if let w = state.settings.workspace { FieldRow(label: "Projects in", value: w.root.path) }
                gateLine
                HStack {
                    Button("Choose…") {
                        if let url = Panels.chooseFolder(title: "Working directory", prompt: "Use This Folder", message: "Adverb makes an Adverb folder here and keeps every project in it.",
                                                         start: state.settings.workdirURL) {
                            Task { await root.chooseWorkdir(url) }
                        }
                    }.buttonStyle(.adverbQuiet)
                    if let w = state.settings.workspace { Button("Reveal") { Panels.reveal([w.root]) }.buttonStyle(.adverbLink) }
                }
            }
        }
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("Music folder")
                FieldRow(label: "Folder", value: state.settings.musicFolder ?? "Not chosen")
                Text("Songs are read where they are and never copied. A folder inside ~/Music/Music needs your permission once; choosing it here grants it.")
                    .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                Button("Choose…") {
                    if let url = Panels.chooseFolder(title: "Music folder", prompt: "Use This Folder", message: "Adverb lists the songs in this folder.",
                                                     start: FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first, canCreate: false) {
                        Task { await root.chooseMusicFolder(url) }
                    }
                }.buttonStyle(.adverbQuiet)
            }
        }
        AdverbCard {
            VStack(alignment: .leading, spacing: .layer2) {
                SectionLabel("Adverb's own settings")
                FieldRow(label: "Settings file", value: AdverbHome.settingsFile.path)
                Button("Reveal") { Panels.reveal([AdverbHome.settingsFile]) }.buttonStyle(.adverbLink)
            }
        }
    }

    @ViewBuilder private var gateLine: some View {
        switch state.gate {
        case .driveNotMounted(let v): Label("\(v) is not plugged in", systemImage: "externaldrive.badge.exclamationmark").adverbType(.caption).foregroundStyle(Color.adverbWarning)
        case .workdirMissing: Label("The folder is gone", systemImage: "exclamationmark.triangle").adverbType(.caption).foregroundStyle(Color.adverbWarning)
        case .ready, .noProjects: Label("Available", systemImage: "checkmark.circle").adverbType(.caption).foregroundStyle(Color.adverbSuccess)
        default: EmptyView()
        }
    }
}
