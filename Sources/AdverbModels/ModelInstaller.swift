//
//  ModelInstaller.swift
//  AdverbModels
//
//  WHAT: A catalog model on this Mac or not, fetched at its pinned commit into the stack's shared
//        home (Frigate's HubDownloader: snapshots/models/<org>/<name>, a copy any Rao app fetched
//        is used where it sits), and removed again.
//  PIN:  Weights are safetensors and nothing else; no Python a repository ships is fetched.
//  PIN:  Only a pinned mirror is downloaded (a revision of 40 hex digits). A catalog entry whose
//        mirror is not published yet says so instead of fetching something unreviewed.
//

import AdverbCore
import Foundation
import FrigateBridge
import MLXLMCommon

public enum ModelInstaller {
    public static let patterns = ["*.safetensors", "*.json", "*.jinja", "*.txt", "*.model", "*.tiktoken"]

    static var home: URL { ModelHome.huggingFace() }

    /// Where a repository sits complete at `revision` (nil: any commit), in the stack's own roots.
    public static func folder(_ id: String, revision: String? = nil) -> URL? {
        HubDownloader.materializedSnapshot(id: id, revision: revision, matching: patterns, roots: HubDownloader.snapshotRoots(home: home))
    }

    public static func isInstalled(_ spec: ModelSpec) -> Bool { folder(spec.id, revision: spec.revision) != nil }

    /// The model's folder: a path, or a repository on this Mac (at its catalog commit when it has one).
    public static func resolve(_ idOrPath: String) -> URL? {
        if idOrPath.hasPrefix("/") || idOrPath.hasPrefix("~") {
            let url = URL(fileURLWithPath: (idOrPath as NSString).expandingTildeInPath, isDirectory: true)
            return FileManager.default.fileExists(atPath: url.appendingPathComponent("config.json").path) ? url : nil
        }
        return folder(idOrPath, revision: ModelCatalog.spec(idOrPath)?.revision) ?? folder(idOrPath)
    }

    public static func download(_ spec: ModelSpec, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let revision = spec.revision else {
            throw ModelError.notInstalled("\(spec.title) is not published under rao-studios yet; it cannot be downloaded.")
        }
        return try await download(spec.id, revision: revision, progress: progress)
    }

    /// Any repository at `revision` ("main" for the probe's own trials).
    public static func download(_ id: String, revision: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await HubDownloader(home: home).download(id: id, revision: revision, matching: patterns, useLatest: false) { p in
            progress(p.fractionCompleted)
        }
    }

    /// Removes the repository's copy in the stack's home (for every Rao app that uses it).
    public static func remove(_ id: String) throws {
        for root in HubDownloader.ownRoots(home: home) {
            let folder = root.appendingPathComponent("models").appendingPathComponent(id)
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        }
    }

    /// Bytes on disk for a folder.
    public static func size(of folder: URL) -> Int64 {
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in items {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }
}
