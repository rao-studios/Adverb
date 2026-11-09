//
//  AdverbRuntimeRoot+Models.swift
//  AdverbRuntime
//
//  WHAT: The models' actions: what is on this Mac (scanned from the stack's home), a model
//        downloaded at its pinned commit from huggingface.co/rao-studios (with its progress), a
//        download cancelled, a model removed, the writer and the eyes chosen.
//  PIN:  A model is shared with every Rao app on the Mac (the same home): removing one says so in
//        Settings first. A download that ends refreshes the gate, so onboarding moves on by itself.
//

import AdverbAgents
import AdverbCore
import AdverbModels
import AdverbVoice
import Foundation

extension AdverbRuntimeRoot {
    /// Searches the models folders again: which catalog models (and the setting's own) are on this
    /// Mac, and where (a copy another Rao app fetched is used where it sits).
    public func refreshModels() async {
        let ids = Array(Swift.Set(ModelCatalog.all.map(\.id) + [settings.textModelID] + [settings.visionModel].compactMap { $0 }))
        let scan = await Task.detached { () -> (Swift.Set<String>, [String: Int64], [String: [ModelCopy]]) in
            var installed = Swift.Set<String>()
            var sizes: [String: Int64] = [:]
            var found: [String: [ModelCopy]] = [:]
            let folders = ModelSearch.scan(ModelHome.searchRoots())
            for id in ids {
                let copies: [ModelCopy]
                if let spec = ModelCatalog.spec(id) {
                    copies = ModelSearch.copies(of: spec, in: folders,
                                                isComplete: spec.slot == .speech ? VoiceLibrary.isComplete : ModelSearch.isCompleteMLX)
                } else {
                    copies = ModelInstaller.resolve(id).map { [ModelCopy(folder: $0, commit: nil, isOwnPath: true, isUpstream: false)] } ?? []
                }
                guard let first = copies.first else { continue }
                installed.insert(id)
                sizes[id] = ModelInstaller.size(of: first.folder)
                found[id] = copies
            }
            return (installed, sizes, found)
        }.value
        models.set(.scanned(installed: scan.0, sizes: scan.1, copies: scan.2))
        models.set(.loaded(Swift.Set(await ModelPool.shared.loadedIDs)))
    }

    /// Fetches a catalog model at its pinned commit, reporting progress; the gate and the voices
    /// are read again when it lands.
    public func downloadModel(_ spec: ModelSpec) {
        guard modelDownloads[spec.id] == nil else { return }
        guard spec.isInstallable else {
            models.set(.problem(spec.id, "\(spec.title) is not published under rao-studios yet."))
            return
        }
        models.set(.downloading(spec.id, 0))
        let service = models
        let id = spec.id
        modelDownloads[id] = Task { @MainActor in
            defer { self.modelDownloads[id] = nil }
            let throttle = ProgressThrottle()
            do {
                let report: @Sendable (Double) -> Void = { p in if throttle.shouldReport(p) { service.set(.downloading(id, p)) } }
                if spec.slot == .speech {
                    _ = try await VoicePackInstaller.download(spec, progress: report)
                } else {
                    _ = try await ModelInstaller.download(spec, progress: report)
                }
                service.set(.downloading(id, nil))
                config.set(.notice("\(spec.title) is on this Mac."))
            } catch is CancellationError {
                service.set(.downloading(id, nil))
            } catch {
                service.set(.problem(id, Task.isCancelled ? nil : "\(error)"))
                if !Task.isCancelled { config.set(.problem("\(spec.title) did not download: \(error)")) }
            }
            await self.refreshModels()
            await self.loadVoices()
            await self.refresh()
        }
    }

    /// The recommended set for this Mac, every part not yet here.
    public func downloadRecommended(includeVoices: Bool = true) {
        let set = models.state.recommended
        var specs = [set.text] + (set.vision.map { [$0] } ?? [])
        if includeVoices { specs += set.speech }
        for spec in specs where !models.state.isInstalled(spec.id) { downloadModel(spec) }
        if settings.textModel == nil { update { $0.textModel = set.text.id } }
    }

    public func cancelDownload(_ id: String) {
        modelDownloads[id]?.cancel()
        modelDownloads[id] = nil
        models.set(.downloading(id, nil))
    }

    /// Removes a model from the stack's home (every Rao app's copy).
    public func removeModel(_ spec: ModelSpec) async {
        cancelDownload(spec.id)
        do {
            await ModelPool.shared.unload(spec.id)
            if spec.slot == .speech {
                try VoicePackInstaller.remove(spec)
            } else {
                try ModelInstaller.remove(spec)
            }
            config.set(.notice("\(spec.title) was removed from this Mac."))
        } catch {
            config.set(.problem("\(spec.title) was not removed: \(error)"))
        }
        await refreshModels()
        await loadVoices()
        await refresh()
    }

    /// The folder models are kept in and looked for from now on (nil: ~/.rao/models). Models loaded
    /// from the old folder stay loaded until the writer changes.
    public func useModelsFolder(_ folder: URL?) async {
        if let folder {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                config.set(.problem("\(ModelHome.display(folder)) is not a folder on this Mac."))
                return
            }
        }
        let chosen = folder.flatMap { $0.standardizedFileURL == ModelHome.defaultRoot().standardizedFileURL ? nil : $0 }
        update { $0.modelsFolder = chosen.map(ModelHome.display) }
        ModelHome.use(chosen)
        VoiceLibrary.shared.unloadAll()
        await refreshModels()
        await loadVoices()
        await refresh()
    }

    /// The writer reads images (it is its own eyes), from its folder or the catalog.
    public var writerReadsImages: Bool { ModelPool.shared.info(settings.textModelID).acceptsImages }

    /// The writer from now on; the one before is unloaded when the new one first writes.
    public func useTextModel(_ id: String) {
        update { $0.textModel = id }
        Task { await refresh() }
    }

    /// The eyes from now on (nil: the writer's own, when it reads images, else none).
    public func useVisionModel(_ id: String?) {
        update { $0.visionModel = id }
    }
}

/// Passes on a download's progress at most every percent, so the service is not written per chunk.
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1.0
    func shouldReport(_ p: Double) -> Bool {
        lock.withLock {
            guard p >= 1 || p - last >= 0.01 else { return false }
            last = p
            return true
        }
    }
}
