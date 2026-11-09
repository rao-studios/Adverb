//
//  VoiceLibrary.swift
//  AdverbVoice
//
//  WHAT: The voice packs on this Mac (ModelCatalog's speech entries, downloaded into the stack's
//        home), their voices, and a loaded engine per pack when one is first spoken with.
//  PIN:  A pack is a folder: Paradee's (ParadeeText/ParadeeAcoustic.mlmodelc and paradee.json) or
//        Kokoro-82M's (kokoro_24_*.mlmodelc and voices/*.json), each with the shared front end
//        (vocab_index.json, the lexicons, the G2P pair). `ADVERB_VOICE_PACKS` (folders, colon
//        separated) adds packs that are not downloaded, for a developer's own conversions.
//  PIN:  Voices are named as Kokoro names them: the first letter the accent (a American, b British,
//        h Hindi…), the second the gender, then the name ("af_heart" → Heart, American female).
//

import AdverbCore
import Foundation

public final class VoiceLibrary: SpeechProvider, @unchecked Sendable {
    public static let shared = VoiceLibrary()

    private let lock = NSLock()
    private var loaded: [String: KokoroSynthesizer] = [:]

    public init() {}

    /// Installed packs, in the catalog's order.
    public var packs: [SpeechPackInfo] {
        var out: [SpeechPackInfo] = []
        for spec in ModelCatalog.speech {
            guard let id = spec.packID, let folder = Self.folder(spec) else { continue }
            out.append(Self.info(id: id, title: spec.title, revision: ModelHome.commit(of: folder, marker: Self.marker(folder)), folder: folder))
        }
        for folder in Self.developerFolders where Self.isComplete(folder) {
            let id = "dev:" + folder.lastPathComponent
            if !out.contains(where: { $0.id == id }) { out.append(Self.info(id: id, title: folder.lastPathComponent, revision: nil, folder: folder)) }
        }
        return out
    }

    public func synthesizer(pack id: String) async throws -> any AdverbCore.SpeechSynthesizer {
        if let ready = lock.withLock({ loaded[id] }) { return ready }
        guard let info = packs.first(where: { $0.id == id }), let folder = Self.folder(forPack: id) else { throw SpeechError.packMissing(id) }
        let synthesizer = try await KokoroSynthesizer(pack: info, directory: folder)
        return lock.withLock {
            if let raced = loaded[id] { return raced }
            loaded[id] = synthesizer
            return synthesizer
        }
    }

    /// Unloads every pack (a pack removed or replaced).
    public func unloadAll() { lock.withLock { loaded.removeAll() } }

    // MARK: - Folders

    /// The pack's copy in the models folders, wherever it sits (ModelSearch: by its pinned commit).
    public static func folder(_ spec: ModelSpec) -> URL? { copies(of: spec).first?.folder }

    public static func copies(of spec: ModelSpec) -> [ModelCopy] {
        ModelSearch.copies(of: spec, roots: ModelHome.searchRoots(), isComplete: isComplete)
    }

    static func folder(forPack id: String) -> URL? {
        if let spec = ModelCatalog.speechSpec(pack: id) { return folder(spec) }
        return developerFolders.first { "dev:" + $0.lastPathComponent == id }
    }

    static var developerFolders: [URL] {
        (ProcessInfo.processInfo.environment["ADVERB_VOICE_PACKS"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: (String($0) as NSString).expandingTildeInPath, isDirectory: true) }
    }

    static func isParadee(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("ParadeeText.mlmodelc").path)
            && FileManager.default.fileExists(atPath: folder.appendingPathComponent("ParadeeAcoustic.mlmodelc").path)
    }

    /// The front end and one acoustic half: what loads.
    public static func isComplete(_ folder: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.appendingPathComponent("vocab_index.json").path),
              fm.fileExists(atPath: folder.appendingPathComponent("us_gold.json").path) else { return false }
        if isParadee(folder) { return true }
        let files = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        return files.contains { $0.hasPrefix("kokoro_") && $0.hasSuffix(".mlmodelc") } && !voiceNames(folder).isEmpty
    }

    /// Kokoro-82M's voices sit in voices/; a student names its own (its loadVoice takes the pack).
    static func voicesFolder(_ folder: URL) -> URL {
        isParadee(folder) ? folder : folder.appendingPathComponent("voices", isDirectory: true)
    }

    static func voiceNames(_ folder: URL) -> [String] { KokoroEngine.availableVoices(in: folder) }

    /// The file whose download metadata names the pack's commit.
    static func marker(_ folder: URL) -> String { "vocab_index.json" }

    static func info(id: String, title: String, revision: String?, folder: URL) -> SpeechPackInfo {
        let paradee = isParadee(folder)
        let voices = voiceNames(folder).map { voice(named: $0, packID: id) }
        return SpeechPackInfo(id: id, title: title, revision: revision, voices: voices, languages: [.english],
                              exactTiming: true, adjustsSpeed: paradee)
    }

    static func voice(named name: String, packID: String) -> SpeechVoice {
        let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
        let code = parts.count == 2 ? parts[0] : ""
        let accent: String = switch code.first {
        case "a": "American"
        case "b": "British"
        case "h": "Hindi"
        case "e": "Spanish"
        case "f": "French"
        case "i": "Italian"
        case "j": "Japanese"
        case "p": "Brazilian"
        case "z": "Mandarin"
        default: ""
        }
        let gender = code.count == 2 ? (code.last == "f" ? "female" : code.last == "m" ? "male" : "") : ""
        let base = parts.count == 2 ? parts[1] : name
        return SpeechVoice(id: name, name: base.prefix(1).uppercased() + base.dropFirst(), packID: packID, language: .english,
                           accent: accent, gender: gender)
    }
}
