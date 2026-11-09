//
//  ModelPool.swift
//  AdverbModels
//
//  WHAT: The models loaded in this process, one container per model, loaded on first use; and the
//        handle the agents are given (`handle(_:)`), which loads its model the first time it is asked
//        to write and says so while it does.
//  PIN:  A Mac holds what it has memory for. Loading a writer unloads the other writers (only one is
//        ever in use); the eyes stay beside it when they are a second model.
//  PIN:  The first GPU call checks mlx.metallib is beside the binary (MLXStack): without it MLX
//        exits the process.
//

import AdverbCore
import Foundation
import FrigateBridge
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM

public actor ModelPool {
    public static let shared = ModelPool()

    private var loaded: [String: MLXLanguageModel] = [:]
    private var loading: [String: Task<MLXLanguageModel, Error>] = [:]
    private var configured = false

    public var loadedIDs: [String] { Array(loaded.keys) }

    /// The model, loaded once. `role` decides what it may unload to make room.
    public func model(_ id: String, slot: ModelSlot = .text, onStatus: @escaping @Sendable (String) -> Void = { _ in }) async throws -> MLXLanguageModel {
        if let model = loaded[id] { return model }
        if let task = loading[id] { return try await task.value }
        try configure()
        if slot == .text {
            for other in loaded.keys where ModelCatalog.spec(other)?.slot != .vision && other != id { unload(other) }
        }
        guard let directory = ModelInstaller.resolve(id) else {
            throw ModelError.notInstalled(id)
        }
        let task = Task<MLXLanguageModel, Error> {
            let files = ModelFiles.load(directory)
            let title = ModelCatalog.spec(id)?.title ?? ModelInfo.shortName(id)
            onStatus("Loading \(title) (\(String(format: "%.1f", Double(ModelInstaller.size(of: directory)) / 1_073_741_824)) GB)")
            await Self.registerAliases()
            let container = try await loadModelContainer(from: directory, using: HubTokenizerLoader())
            let isVision = await container.perform { UncheckedBox($0.model is any VLMModel) }.value
            var info = files?.info(id: id) ?? ModelInfo(id: id)
            info.acceptsImages = isVision
            return MLXLanguageModel(container: container, info: info, files: files, isVision: isVision)
        }
        loading[id] = task
        defer { loading[id] = nil }
        do {
            let model = try await task.value
            loaded[id] = model
            return model
        } catch {
            throw ModelError.loadFailed("\(ModelInfo.shortName(id)): \(error)")
        }
    }

    public func unload(_ id: String) {
        guard loaded.removeValue(forKey: id) != nil else { return }
        Memory.clearCache()
    }

    public func unloadAll() {
        loaded.removeAll()
        Memory.clearCache()
    }

    /// What a model folder says it is, without loading it.
    public nonisolated func info(_ id: String) -> ModelInfo {
        if let directory = ModelInstaller.resolve(id), let files = ModelFiles.load(directory) { return files.info(id: id) }
        if let spec = ModelCatalog.spec(id) {
            return ModelInfo(id: id, revision: spec.revision, title: spec.title, contextTokens: spec.contextTokens,
                             acceptsImages: spec.acceptsImages, thinks: spec.family.hasPrefix("qwen3") || spec.family == "nemotron_h")
        }
        return ModelInfo(id: id)
    }

    /// A handle that loads `id` when it is first asked to write.
    public nonisolated func handle(_ id: String, slot: ModelSlot = .text) -> any AdverbCore.LanguageModel {
        LazyLanguageModel(id: id, slot: slot, info: info(id), pool: self)
    }

    private func configure() throws {
        guard !configured else { return }
        let memoryMB = Int(ProcessInfo.processInfo.physicalMemory >> 20)
        // MLX's buffer pool, bounded: it recycles rather than grows past an eighth of memory.
        try MLXStack.configureMemory(cacheLimitMB: min(8_192, memoryMB / 8), memoryLimitMB: memoryMB * 3 / 4)
        configured = true
    }

    /// Model types Frigate's registry does not name, for architectures it builds (Craft's aliases).
    static func registerAliases() async {
        let registry = LLMTypeRegistry.shared
        if await !registry.contains("ministral3") {
            await registry.registerModelType("ministral3") { data in
                Mistral3TextModel(try JSONDecoder().decode(Mistral3TextConfiguration.self, from: data))
            }
        }
    }
}

/// A model the agents can hold before it is loaded: the first call loads it (and says so).
struct LazyLanguageModel: AdverbCore.LanguageModel {
    let id: String
    let slot: ModelSlot
    let info: ModelInfo
    let pool: ModelPool

    func complete(_ request: ModelRequest, onEvent: @escaping @Sendable (ModelEvent) -> Void) async throws -> ModelAnswer {
        let model = try await pool.model(id, slot: slot) { onEvent(.status($0)) }
        return try await model.complete(request, onEvent: onEvent)
    }
}
