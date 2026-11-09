//
//  VoicePackInstaller.swift
//  AdverbVoice
//
//  WHAT: A voice pack fetched at its pinned commit from huggingface.co/rao-studios into the stack's
//        home (snapshots/models/<org>/<name>), checked complete, and removed again.
//  PIN:  Not Frigate's HubDownloader: it wants config.json and safetensors, and a pack is Core ML
//        folders and JSON. The same Hub client fetches it, file by file, with the same metadata, so
//        `ModelHome.commit` reads its commit.
//

import AdverbCore
import Foundation
import Hub

public enum VoicePackInstaller {
    public static func isInstalled(_ spec: ModelSpec) -> Bool { VoiceLibrary.folder(spec) != nil }

    public static func download(_ spec: ModelSpec, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let revision = spec.revision else {
            throw ModelError.notInstalled("\(spec.title) is not published under rao-studios yet; it cannot be downloaded.")
        }
        let hub = HubApi(downloadBase: ModelHome.snapshots(), cache: nil)
        let folder = try await hub.snapshot(from: spec.id, revision: revision, matching: []) { p in progress(p.fractionCompleted) }
        guard VoiceLibrary.isComplete(folder) else {
            throw SpeechError.failed("\(spec.title) downloaded incomplete; download it again.")
        }
        VoiceLibrary.shared.unloadAll()
        return folder
    }

    /// Removes every copy of the pack the search finds.
    public static func remove(_ spec: ModelSpec) throws {
        VoiceLibrary.shared.unloadAll()
        for copy in VoiceLibrary.copies(of: spec) { try FileManager.default.removeItem(at: copy.folder) }
    }
}
