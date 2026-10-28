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
//        from elsewhere. Reading the Keychain spawns /usr/bin/security: never on main.
//

import AdverbAgents
import AdverbCore
import AdverbRender
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

    /// The key, once read, so a run's compute resolves without a process.
    var apiKey: Secret?
    var keyStore: KeyStore = KeychainKeyStore()
    /// The ElevenLabs key, once read. Optional: without it campaigns stay silent.
    var voiceKey: Secret?
    var voiceKeyStore: KeyStore = KeychainKeyStore(account: KeychainKeyStore.elevenLabsAccount)
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
        await reloadKey()
        await reloadVoiceKey()
        await refresh()
        if let folder = settings.musicFolder { Task { await self.scanMusic(URL(fileURLWithPath: folder, isDirectory: true)) } }
    }

    /// Everything read again from disk: the gate, the projects, their campaigns.
    public func refresh() async {
        let gate = evaluateGate()
        if case .driveNotMounted = gate { config.set(.gate(gate)); return }
        if case .workdirMissing = gate { config.set(.gate(gate)); return }
        if gate == .needsKey || gate == .needsWorkdir { config.set(.gate(gate)); return }
        await reloadProjects()
        config.set(.gate(projectCount == 0 ? .noProjects : .ready))
    }

    func evaluateGate() -> Gate {
        guard apiKey != nil else { return .needsKey }
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

    // MARK: - Key

    func reloadKey() async {
        let store = keyStore
        let resolved = await Task.detached { KeyResolver(store: store, environment: ProcessInfo.processInfo.environment).resolve() }.value
        apiKey = resolved?.secret
        config.set(.key(source: resolved?.source, masked: resolved?.secret.masked))
    }

    /// Saves the key to the Keychain, then checks it against the API.
    public func saveKey(_ text: String) async -> Bool {
        guard let secret = Secret(text) else { config.set(.problem("That key is empty.")); return false }
        let store = keyStore
        do {
            try await Task.detached { try store.write(secret) }.value
        } catch {
            config.set(.problem("The key was not saved: \(error)"))
            return false
        }
        await reloadKey()
        await testKey()
        await refresh()
        return true
    }

    public func forgetKey() async {
        let store = keyStore
        try? await Task.detached { try store.forget() }.value
        await reloadKey()
        await refresh()
    }

    /// A free call that proves the key and the model: GET /v1/models/{model}.
    @discardableResult
    public func testKey() async -> Bool {
        guard let apiKey else { config.set(.keyChecked(false)); return false }
        let client = ClaudeClient(config: ClaudeConfig(apiKey: apiKey, model: settings.model))
        do {
            try await client.ping()
            config.set(.keyChecked(true))
            config.set(.notice("The key works with \(settings.model)."))
            return true
        } catch {
            config.set(.keyChecked(false))
            config.set(.problem("\(error)"))
            return false
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

    func compute() throws -> AdverbCompute {
        guard let apiKey else { throw ClaudeError.noKey }
        guard let workspace else { throw WorkspaceError.noWorkdir }
        guard VolumeGate.isUsable(workspace.gate) else { throw WorkspaceError.unavailable(workspace.gate) }
        let s = settings
        let client = ClaudeClient(config: ClaudeConfig(apiKey: apiKey, model: s.model, effort: s.effort, fallbacks: s.fallbacks))
        return AdverbCompute(client: client, prompts: try PromptLibrary.load(skillPath: s.skillPath), workspace: workspace, settings: s,
                             voice: voiceClient)
    }

    func attachAgents() {
        let resolve: @Sendable (Any) async throws -> AdverbCompute = { _ in try await MainActor.run { try AdverbRuntimeRoot.shared.compute() } }
        generation.center.$planner.attach { try await resolve($0) }
        generation.center.$builder.attach { try await resolve($0) }
        generation.center.$retimer.attach { try await resolve($0) }
        generation.center.$voicer.attach { try await resolve($0) }
    }
}
