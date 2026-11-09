//
//  ModelRow.swift
//  Adverb
//
//  WHAT: One model as onboarding and Settings show it: what it is and is for, its size, and where it
//        stands on this Mac — installed (and in use), downloading (how far, Cancel), or Download.
//  IN:   ModelService's state (installed, downloading, problems), the spec
//  OUT:  AdverbRuntimeRoot (downloadModel, cancelDownload, removeModel, useTextModel)
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct ModelRow: View {
    let spec: ModelSpec
    let state: ModelService.Center.State
    /// It is the one this Mac uses for its slot (shown only once it is installed).
    var inUse = false
    /// Offered first for this Mac's memory (onboarding).
    var recommended = false
    /// Offer "Use" when installed and not in use.
    var canUse = false
    /// Offer "Remove" when installed.
    var canRemove = false
    var onUse: () -> Void = {}
    @State private var confirmRemove = false

    var body: some View {
        RowCard(selected: inUse && state.isInstalled(spec.id)) {
            VStack(alignment: .leading, spacing: .snug) {
                HStack(alignment: .firstTextBaseline, spacing: .layer2) {
                    Text(spec.title).adverbType(.labelStrong).foregroundStyle(Color.adverbInk)
                    AdverbBadge(text: spec.slot.title)
                    if inUse, state.isInstalled(spec.id) { AdverbBadge(text: "In use", color: .adverbGold) }
                    if recommended { AdverbBadge(text: "For this Mac", color: .adverbGold) }
                    Spacer(minLength: .layer2)
                    Text(sizeLine).adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                }
                Text(spec.summary).adverbType(.caption).foregroundStyle(Color.adverbInkSoft).fixedSize(horizontal: false, vertical: true)
                status
                if state.isInstalled(spec.id), let foundLine {
                    Text(foundLine).adverbType(.caption).foregroundStyle(Color.adverbInkDim).textSelection(.enabled)
                }
                if let problem = state.problems[spec.id] {
                    Text(problem).adverbType(.caption).foregroundStyle(Color.adverbError).textSelection(.enabled)
                }
            }
        }
        .confirmationDialog("Remove \(spec.title)?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { Task { await AdverbRuntimeRoot.shared.removeModel(spec) } }
        } message: {
            Text(removeMessage)
        }
    }

    /// Where the copy it loads from sits, when that is not its own download (another app's copy, or
    /// the repository it mirrors).
    private var foundLine: String? {
        guard let copy = state.copies[spec.id]?.first, !copy.isOwnPath else { return nil }
        let path = ModelHome.display(copy.folder)
        if copy.isUpstream, let source = spec.sameWeights { return "Using \(source.repo)'s copy, the same weights: \(path)" }
        return "Using the copy at \(path)"
    }

    private var removeMessage: String {
        let paths = (state.copies[spec.id] ?? []).map { ModelHome.display($0.folder) }
        let what = paths.isEmpty ? "It is removed" : paths.count == 1 ? "\(paths[0]) is removed" : "Its \(paths.count) copies (\(paths.joined(separator: ", "))) are removed"
        return "\(what) from this Mac, for every Rao app that uses \(paths.count > 1 ? "them" : "it"). It can be downloaded again."
    }

    private var sizeLine: String {
        if let bytes = state.sizes[spec.id], bytes > 0 { return Self.size(bytes) + " on this Mac" }
        return spec.sizeLabel
    }

    static func size(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }

    @ViewBuilder private var status: some View {
        let root = AdverbRuntimeRoot.shared
        if let fraction = state.downloading[spec.id] {
            HStack(spacing: .layer2) {
                AdverbMeter(fraction: fraction)
                Text("\(Int((fraction * 100).rounded())) %").adverbType(.caption).foregroundStyle(Color.adverbInkDim).monospacedDigit()
                Button("Cancel") { root.cancelDownload(spec.id) }.buttonStyle(.adverbLink)
            }
        } else if state.isInstalled(spec.id) {
            HStack(spacing: .layer2) {
                Label("On this Mac", systemImage: "checkmark.circle.fill").adverbType(.caption).foregroundStyle(Color.adverbGold)
                Spacer()
                if canUse, !inUse { Button("Use", action: onUse).buttonStyle(.adverbQuiet) }
                if canRemove { Button("Remove") { confirmRemove = true }.buttonStyle(.adverbLink) }
            }
        } else {
            HStack(spacing: .layer2) {
                if !spec.fits(memoryGB: state.memoryGB) {
                    Text("Wants \(spec.minimumMemoryGB) GB of memory; this Mac has \(state.memoryGB) GB.")
                        .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                }
                Spacer()
                if spec.isInstallable {
                    Button("Download") { root.downloadModel(spec) }.buttonStyle(.adverbQuiet)
                } else {
                    Text("Not published yet").adverbType(.caption).foregroundStyle(Color.adverbInkMuted)
                }
            }
        }
    }
}
