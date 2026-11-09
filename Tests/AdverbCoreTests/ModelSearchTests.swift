import Foundation
import Testing
@testable import AdverbCore

/// A catalog model is found by the commit its files were downloaded at, wherever it sits in the
/// models folders, and under its upstream's name when the mirror copies those bytes.
@Suite(.serialized) struct ModelSearchTests {
    static let revision = String(repeating: "a", count: 40)
    static let source = String(repeating: "b", count: 40)
    static let spec = ModelSpec(id: "rao-studios/m-mlx-4bit", revision: revision, slot: .text, title: "M", summary: "", family: "gemma4",
                                downloadBytes: 1, minimumMemoryGB: 8, upstream: "up/m-4bit", sameWeightsAs: "up/m-4bit@\(source)")

    /// A model folder: config.json, one shard, and the Hub client's metadata naming `commit`.
    @discardableResult
    static func model(_ root: URL, _ path: String, commit: String?, weights: Bool = true, marker: String = "config.json") throws -> URL {
        let folder = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appendingPathComponent(marker))
        if weights { try Data([1, 2, 3]).write(to: folder.appendingPathComponent("model.safetensors")) }
        if let commit {
            let meta = folder.appendingPathComponent(".cache/huggingface/download", isDirectory: true)
            try FileManager.default.createDirectory(at: meta, withIntermediateDirectories: true)
            try "\(commit)\netag\n1790000000\n".write(to: meta.appendingPathComponent("\(marker).metadata"), atomically: true, encoding: .utf8)
        }
        return folder
    }

    @Test func theOwnCopyFirstThenOthersThenTheUpstream() throws {
        let root = Fixture.temp()
        let upstream = try Self.model(root, "huggingface/snapshots/models/up/m-4bit", commit: Self.source)
        let elsewhere = try Self.model(root, "moved/by/hand/m", commit: Self.revision)
        let own = try Self.model(root, "huggingface/snapshots/models/rao-studios/m-mlx-4bit", commit: Self.revision)
        try Self.model(root, "huggingface/snapshots/models/rao-studios/stale", commit: String(repeating: "c", count: 40))
        try Self.model(root, "huggingface/snapshots/models/rao-studios/partial", commit: Self.revision, weights: false)
        try Self.model(root, "pack/x.mlmodelc/inner", commit: Self.revision)

        let copies = ModelSearch.copies(of: Self.spec, roots: [root], isComplete: ModelSearch.isCompleteMLX)
        #expect(copies.map(\.folder.standardizedFileURL) == [own, elsewhere, upstream].map(\.standardizedFileURL))
        #expect(copies.map(\.isOwnPath) == [true, false, false])
        #expect(copies.map(\.isUpstream) == [false, false, true])
    }

    @Test func theUpstreamAloneIsTheModel() throws {
        let root = Fixture.temp()
        let upstream = try Self.model(root, "huggingface/snapshots/models/up/m-4bit", commit: Self.source)
        let copy = try #require(ModelSearch.copy(of: Self.spec, roots: [root], isComplete: ModelSearch.isCompleteMLX))
        #expect(copy.folder.standardizedFileURL == upstream.standardizedFileURL && copy.isUpstream)

        var conversion = Self.spec
        conversion.sameWeightsAs = nil
        #expect(ModelSearch.copy(of: conversion, roots: [root], isComplete: ModelSearch.isCompleteMLX) == nil,
                "a model Rao converted itself is only its own repository")
    }

    @Test func aCopyWithoutMetadataCountsOnlyAtItsOwnPath() throws {
        let root = Fixture.temp()
        try Self.model(root, "loose/m", commit: nil)
        #expect(ModelSearch.copy(of: Self.spec, roots: [root], isComplete: ModelSearch.isCompleteMLX) == nil)
        let own = try Self.model(root, "huggingface/snapshots/models/rao-studios/m-mlx-4bit", commit: nil)
        #expect(ModelSearch.copy(of: Self.spec, roots: [root], isComplete: ModelSearch.isCompleteMLX)?.folder.standardizedFileURL
                == own.standardizedFileURL)
    }

    @Test func aVoicePackIsFoundByItsOwnMarker() throws {
        let root = Fixture.temp()
        let pack = ModelSpec(id: "rao-studios/pack", revision: Self.revision, slot: .speech, title: "P", summary: "", family: "kokoro",
                             downloadBytes: 1, minimumMemoryGB: 8, upstream: "", packID: "p")
        let folder = try Self.model(root, "elsewhere/pack", commit: Self.revision, weights: false, marker: "vocab_index.json")
        let found = ModelSearch.copy(of: pack, roots: [root]) { FileManager.default.fileExists(atPath: $0.appendingPathComponent("vocab_index.json").path) }
        #expect(found?.folder.standardizedFileURL == folder.standardizedFileURL)
    }

    @Test func theChosenFolderIsSearchedBesideTheStacks() {
        defer { ModelHome.use(nil) }
        let chosen = URL(fileURLWithPath: "/Volumes/Models", isDirectory: true)
        ModelHome.use(chosen)
        #expect(ModelHome.root() == chosen.standardizedFileURL)
        #expect(ModelHome.searchRoots() == [chosen.standardizedFileURL, ModelHome.defaultRoot()])
        #expect(ModelHome.folder("org/name").path == "/Volumes/Models/huggingface/snapshots/models/org/name")
        ModelHome.use(nil)
        #expect(ModelHome.searchRoots() == [ModelHome.defaultRoot()])
        #expect(ModelHome.display(ModelHome.defaultRoot()).hasPrefix("~/") || ProcessInfo.processInfo.environment["AII_HOME"] != nil)
    }

    @Test func theFolderSettingDecodes() throws {
        let s = try JSONDecoder().decode(AdverbSettings.self, from: Data(#"{"modelsFolder":"~/Models"}"#.utf8))
        #expect(s.modelsFolderURL?.path == NSHomeDirectory() + "/Models")
        #expect(try JSONDecoder().decode(AdverbSettings.self, from: Data(#"{"modelsFolder":""}"#.utf8)).modelsFolder == nil)
        #expect(AdverbSettings().modelsFolderURL == nil)
    }

    @Test func aMirrorNamesTheBytesItCopies() {
        for spec in ModelCatalog.all {
            guard let source = spec.sameWeights else { continue }
            #expect(source.repo.contains("/") && source.commit.count == 40 && source.commit.allSatisfy(\.isHexDigit), "\(spec.id)")
        }
        #expect(ModelCatalog.gemma4.sameWeights?.repo == "mlx-community/gemma-4-31b-it-4bit")
    }
}
