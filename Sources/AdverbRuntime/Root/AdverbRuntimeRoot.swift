//
//  AdverbRuntimeRoot.swift
//  AdverbRuntime
//
//  WHAT: The composition root: the one object holding a relay to every service, which makes it
//        the executor of every reducer, and the place every action that does work lives (Craft's
//        CraftRuntimeRoot). Views call it; it writes files through the stores and the result
//        back into the services.
//  PIN:  A relay is live from its init, so this object holding them keeps the services alive.
//        Granite's send is main-only: the root is @MainActor and the services hop when written
//        from elsewhere. Scanning the models home reads the disk: never on main.
//  PIN:  NOTHING HERE CALLS A REMOTE API. The writer, the eyes and the voices run on this Mac
//        (AdverbModels, AdverbVoice); the only network use is downloading a pinned model.
//

import AdverbAgents
import AdverbCore
import AdverbModels
import AdverbRender
import AdverbVoice
import AppKit
import Foundation
import Granite

@MainActor
public final class AdverbRuntimeRoot {
    public static let shared: AdverbRuntimeRoot = {
        GraniteLogger.currentLevel = .error
        return AdverbRuntimeRoot()
    }()

    @Relay(.silence) public var config: ConfigService
    @Relay(.silence) public var projects: ProjectService
    @Relay(.silence) public var campaigns: CampaignService
    @Relay(.silence) public var generation: GenerationService
    @Relay(.silence) public var music: MusicService
    @Relay(.silence) public var voice: VoiceService
    @Relay(.silence) public var models: ModelService

    /// Downloads under way, by model id: Cancel stops them.
    var modelDownloads: [String: Task<Void, Never>] = [:]
    /// The voice preview playing, and the task that marks it done.
    var previewingVoice: String?
    var previewTask: Task<Void, Never>?
    var observers: [NSObjectProtocol] = []
    var booted = false
    /// The root's own copy of what it last wrote. PIN: a service's state is updated by its reducer
    /// after `set` returns; the root decides from these, never from a state it just wrote.
    var currentSettings = AdverbSettings()
    var projectCount = 0
    /// One-at-a-time build queues, per campaign: Stop cancels the queue with the run.
    var buildQueues: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]

    init() {}

    public var settings: AdverbSettings { currentSettings }
    public var workspace: Workspace? { settings.workspace }

    // MARK: - Boot

    public func boot() async {
        guard !booted else { return }
        booted = true
        let settings = AdverbSettings.load()
        currentSettings = settings
        config.set(.settings(settings))
        attachAgents()
        watchVolumes()
        await refreshModels()
        await loadVoices()
        await refresh()
        if let folder = settings.musicFolder { Task { await self.scanMusic(URL(fileURLWithPath: folder, isDirectory: true)) } }
    }

    /// Everything read again from disk: the gate, the projects, their campaigns.
    public func refresh() async {
        let gate = evaluateGate()
        if case .driveNotMounted = gate { config.set(.gate(gate)); return }
        if case .workdirMissing = gate { config.set(.gate(gate)); return }
        if gate == .needsModels || gate == .needsWorkdir { config.set(.gate(gate)); return }
        await reloadProjects()
        config.set(.gate(projectCount == 0 ? .noProjects : .ready))
    }

    func evaluateGate() -> Gate {
        guard hasWriter else { return .needsModels }
        guard let workspace else { return .needsWorkdir }
        switch workspace.gate {
        case .notMounted(let volume): return .driveNotMounted(volume)
        case .missing: return .workdirMissing(workspace.workdir.path)
        case .mounted, .bootVolume: return .ready
        }
    }

    func watchVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in await AdverbRuntimeRoot.shared.refresh() }
            })
        }
    }

    // MARK: - Settings

    public func update(_ change: (inout AdverbSettings) -> Void) {
        var s = settings
        change(&s)
        do {
            try s.save()
            currentSettings = s
            config.set(.settings(s))
        } catch {
            config.set(.problem("Settings were not saved: \(error.localizedDescription)"))
        }
    }

    // MARK: - Working directory

    public func chooseWorkdir(_ url: URL) async {
        let workspace = Workspace(workdir: url)
        do {
            try workspace.prepare()
        } catch {
            config.set(.problem("\(error)"))
            return
        }
        update { $0.workdir = url.standardizedFileURL.path }
        config.set(.notice("Adverb keeps its projects in \(workspace.root.path)."))
        await refresh()
    }

    // MARK: - Compute

    /// The writer this Mac uses is on it.
    public var hasWriter: Bool { ModelInstaller.resolve(settings.textModelID) != nil }

    func compute() throws -> AdverbCompute {
        guard let workspace else { throw WorkspaceError.noWorkdir }
        guard VolumeGate.isUsable(workspace.gate) else { throw WorkspaceError.unavailable(workspace.gate) }
        let s = settings
        let textID = s.textModelID
        // A writer that is not on this Mac fails only the steps that write: a warp re-cut or a
        // voice step on lines already written still runs.
        let text: any LanguageModel = ModelInstaller.resolve(textID) != nil
            ? ModelPool.shared.handle(textID, slot: .text) : MissingLanguageModel(id: textID)
        var vision: (any LanguageModel)?
        if text.info.acceptsImages {
            vision = text
        } else if let eyes = s.visionModel ?? ModelCatalog.spec(textID).flatMap({ ModelCatalog.vision(for: $0)?.id }),
                  ModelInstaller.resolve(eyes) != nil {
            vision = ModelPool.shared.handle(eyes, slot: .vision)
        }
        let voices: (any SpeechProvider)? = VoiceLibrary.shared.packs.isEmpty ? nil : VoiceLibrary.shared
        return AdverbCompute(text: text, vision: vision, voice: voices, prompts: try PromptLibrary.load(skillPath: s.skillPath),
                             workspace: workspace, settings: s)
    }

    func attachAgents() {
        let resolve: @Sendable (Any) async throws -> AdverbCompute = { _ in try await MainActor.run { try AdverbRuntimeRoot.shared.compute() } }
        generation.center.$planner.attach { try await resolve($0) }
        generation.center.$drafter.attach { try await resolve($0) }
        generation.center.$renderer.attach { try await resolve($0) }
        generation.center.$retimer.attach { try await resolve($0) }
        generation.center.$voicer.attach { try await resolve($0) }
    }
}

/// The writer the settings name when it is not on this Mac: every call says so.
struct MissingLanguageModel: LanguageModel {
    let id: String
    var info: ModelInfo { ModelInfo(id: id, title: ModelCatalog.spec(id)?.title) }
    func complete(_ request: ModelRequest, onEvent: @escaping @Sendable (ModelEvent) -> Void) async throws -> ModelAnswer {
        throw ModelError.notInstalled(id)
    }
}
