//
//  ModelSearch.swift
//  AdverbCore
//
//  WHAT: Finds a catalog model already on this Mac, anywhere in the models folders: every folder
//        holding a model (config.json, or a voice pack's vocab_index.json) is read for the commit its
//        files were downloaded at, and a copy is one at the model's pinned commit — or at the commit
//        of the repository it mirrors byte for byte (`ModelSpec.sameWeightsAs`), so mlx-community's
//        Gemma 4, fetched by another app, is Adverb's Gemma 4 without a second download.
//  PIN:  Identity is the commit, never the folder's name: the Hub client writes it beside each file
//        it fetches (`.cache/huggingface/download/<file>.metadata`), and a commit names exactly one
//        set of files. A folder without that metadata (copied by hand) is used only at the path
//        Adverb downloads the repository to, as before.
//  PIN:  Folders, not files, are walked: a model folder is not descended into, nor a Core ML
//        package, nor anything hidden, so a search of a few dozen models is a few hundred stats.
//

import Foundation

/// A model's folder on this Mac.
public struct ModelCopy: Sendable, Equatable, Hashable {
    public var folder: URL
    /// The commit its files were downloaded at (nil: no download metadata).
    public var commit: String?
    /// It sits where Adverb downloads this repository (…/models/<org>/<name>).
    public var isOwnPath: Bool
    /// It is the repository the model mirrors, not the mirror (the same bytes).
    public var isUpstream: Bool

    public init(folder: URL, commit: String?, isOwnPath: Bool, isUpstream: Bool) {
        self.folder = folder; self.commit = commit; self.isOwnPath = isOwnPath; self.isUpstream = isUpstream
    }
}

public enum ModelSearch {
    /// The files whose download metadata names a folder's commit, in the order they are tried.
    public static let markers = ["config.json", "vocab_index.json"]

    /// Every model folder under `roots`, to `depth` levels, with the commit it was downloaded at.
    public static func scan(_ roots: [URL], depth: Int = 8) -> [(folder: URL, commit: String?)] {
        let fm = FileManager.default
        var out: [(folder: URL, commit: String?)] = []
        var seen = Set<String>()
        func take(_ url: URL) -> Bool {
            guard markers.contains(where: { fm.fileExists(atPath: url.appendingPathComponent($0).path) }) else { return false }
            let commit = markers.lazy.compactMap { ModelHome.commit(of: url, marker: $0) }.first
            if seen.insert(url.standardizedFileURL.path).inserted { out.append((url, commit)) }
            return true
        }
        for root in roots {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            if take(root) { continue }
            guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                           options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walk {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                if ["mlmodelc", "mlpackage"].contains(url.pathExtension) || walk.level > depth { walk.skipDescendants(); continue }
                if take(url) { walk.skipDescendants() }
            }
        }
        return out
    }

    /// Every complete copy of `spec` in `found`, best first: the repository at its pinned commit
    /// where Adverb downloads it, then at that commit anywhere, then the repository it mirrors at
    /// the mirrored commit. Then, for a folder with no download metadata, the download path.
    public static func copies(of spec: ModelSpec, in found: [(folder: URL, commit: String?)],
                              isComplete: (URL) -> Bool) -> [ModelCopy] {
        let source = spec.sameWeights
        var copies: [(rank: Int, copy: ModelCopy)] = []
        for (folder, commit) in found {
            let own = isNamed(folder, spec.id)
            let rank: Int
            if let commit, let revision = spec.revision, commit.lowercased() == revision.lowercased() {
                rank = own ? 0 : 1
            } else if let commit, let source, commit.lowercased() == source.commit.lowercased() {
                rank = 2
            } else if commit == nil, own {
                rank = 3
            } else {
                continue
            }
            guard isComplete(folder) else { continue }
            copies.append((rank, ModelCopy(folder: folder, commit: commit, isOwnPath: own, isUpstream: rank == 2)))
        }
        return copies.sorted { $0.rank < $1.rank }.map(\.copy)
    }

    public static func copies(of spec: ModelSpec, roots: [URL], isComplete: (URL) -> Bool) -> [ModelCopy] {
        copies(of: spec, in: scan(roots), isComplete: isComplete)
    }

    /// The copy a model loads from: the best of `copies`.
    public static func copy(of spec: ModelSpec, roots: [URL], isComplete: (URL) -> Bool) -> ModelCopy? {
        copies(of: spec, roots: roots, isComplete: isComplete).first
    }

    /// The folder is `…/models/<org>/<name>` for `repo` (the layout every Rao download uses).
    static func isNamed(_ folder: URL, _ repo: String) -> Bool {
        folder.standardizedFileURL.path.lowercased().hasSuffix("/models/" + repo.lowercased())
    }

    // MARK: - Complete

    /// An MLX model that loads: config.json, and every shard the safetensors index names (else
    /// model.safetensors, else any safetensors), each non-empty. Frigate's own check, which it keeps private.
    public static func isCompleteMLX(_ folder: URL) -> Bool {
        guard size(folder.appendingPathComponent("config.json")) > 0 else { return false }
        let index = folder.appendingPathComponent("model.safetensors.index.json")
        if FileManager.default.fileExists(atPath: index.path) {
            guard let data = try? Data(contentsOf: index),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let map = object["weight_map"] as? [String: String], !map.isEmpty else { return false }
            return Set(map.values).allSatisfy { size(folder.appendingPathComponent($0)) > 0 }
        }
        if size(folder.appendingPathComponent("model.safetensors")) > 0 { return true }
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return entries.contains { $0.pathExtension == "safetensors" && size($0) > 0 }
    }

    static func size(_ file: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
