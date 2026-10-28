//
//  AdverbRuntimeRoot+Voice.swift
//  AdverbRuntime
//
//  WHAT: The voice-over's actions: the ElevenLabs key (saved, checked, forgotten), the voices and
//        their previews, narrating a day, confirming its English, and making its languages.
//  PIN:  The key is optional and never gates the app. Previews are ElevenLabs' public mp3s,
//        fetched once into the caches folder and played from there.
//

import AdverbAgents
import AdverbCore
import AdverbRender
import Foundation

extension AdverbRuntimeRoot {

    // MARK: - Key

    /// The root's own answer (a service's state lags a turn behind a write).
    public var hasVoiceKey: Bool { voiceKey != nil }

    var voiceClient: ElevenLabsClient? { voiceKey.map { ElevenLabsClient(config: ElevenLabsConfig(apiKey: $0)) } }

    func reloadVoiceKey() async {
        let store = voiceKeyStore
        let resolved = await Task.detached {
            KeyResolver(store: store, environment: ProcessInfo.processInfo.environment, envName: KeyResolver.elevenLabsEnv).resolve()
        }.value
        voiceKey = resolved?.secret
        config.set(.voiceKey(source: resolved?.source, masked: resolved?.secret.masked))
    }

    /// Saves the ElevenLabs key to the Keychain, checks it, and lists the voices it can use.
    public func saveVoiceKey(_ text: String) async -> Bool {
        guard let secret = Secret(text) else { config.set(.problem("That key is empty.")); return false }
        let store = voiceKeyStore
        do {
            try await Task.detached { try store.write(secret) }.value
        } catch {
            config.set(.problem("The ElevenLabs key was not saved: \(error)"))
            return false
        }
        await reloadVoiceKey()
        if await testVoiceKey() { await loadVoices(force: true) }
        return true
    }

    public func forgetVoiceKey() async {
        let store = voiceKeyStore
        try? await Task.detached { try store.forget() }.value
        await reloadVoiceKey()
    }

    /// A free call that proves the key: the subscription, with the characters left this period.
    @discardableResult
    public func testVoiceKey() async -> Bool {
        guard let client = voiceClient else { config.set(.voiceKeyChecked(false)); return false }
        do {
            let quota = try await client.ping()
            config.set(.voiceKeyChecked(true))
            config.set(.voiceQuota(quota))
            config.set(.notice("The ElevenLabs key works: \(quota.used.formatted()) of \(quota.limit.formatted()) characters used this period."))
            return true
        } catch {
            config.set(.voiceKeyChecked(false))
            config.set(.problem("\(error)"))
            return false
        }
    }

    // MARK: - Voices

    var voicesFile: URL { AdverbHome.voices.appendingPathComponent("voices.json") }

    /// The voices: from memory, else the copy on disk (so a picker opens at once), then the API
    /// when there is a key and the list is over an hour old (or `force`).
    public func loadVoices(force: Bool = false) async {
        if !force, !voice.state.voices.isEmpty, let at = voice.state.loadedAt, Date().timeIntervalSince(at) < 3600 { return }
        if voice.state.voices.isEmpty, let saved = try? JSONCoding.read([ElevenVoice].self, from: voicesFile) {
            let at = (try? voicesFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            voice.set(.voices(saved, at: at))
            if !force, Date().timeIntervalSince(at) < 3600 { voice.set(.cachedAll(Self.cachedPreviews())); return }
        }
        voice.set(.cachedAll(Self.cachedPreviews()))
        guard let client = voiceClient else {
            voice.set(.failed("Add an ElevenLabs key to list the voices."))
            return
        }
        voice.set(.loading)
        do {
            let list = try await client.voices()
            try? JSONCoding.write(list, to: voicesFile)
            voice.set(.voices(list, at: Date()))
        } catch {
            voice.set(.failed("\(error)"))
        }
    }

    static func cachedPreviews() -> Swift.Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: AdverbHome.voices.path)) ?? []
        return Swift.Set(files.filter { $0.hasSuffix(".mp3") }.map { String($0.dropLast(4)) })
    }

    /// Plays a voice's preview, or stops it if it is the one playing.
    public func previewVoice(_ id: String) async {
        if previewingVoice == id { stopPreview(); return }
        stopPreview()
        guard let remote = voice.state.voice(id)?.previewURL else {
            config.set(.notice("ElevenLabs has no preview for this voice."))
            return
        }
        previewingVoice = id
        voice.set(.previewing(id))
        let file = AdverbHome.voices.appendingPathComponent("\(id).mp3")
        if !FileManager.default.fileExists(atPath: file.path) {
            do {
                let (temp, response) = try await URLSession.shared.download(from: remote)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw ElevenLabsError.http(http.statusCode, "") }
                try FileManager.default.createDirectory(at: AdverbHome.voices, withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: file)
                try FileManager.default.moveItem(at: temp, to: file)
                voice.set(.cached(id))
            } catch {
                if previewingVoice == id { stopPreview() }
                config.set(.problem("The preview could not be fetched: \(error.localizedDescription)"))
                return
            }
            // The person moved on while it downloaded.
            guard previewingVoice == id else { return }
        }
        playPreview(file, as: id)
    }

    /// Plays a clip on disk (a line of narration), marked as `tag` while it plays.
    public func playClip(_ url: URL, as tag: String) {
        if previewingVoice == tag { stopPreview(); return }
        stopPreview()
        previewingVoice = tag
        voice.set(.previewing(tag))
        playPreview(url, as: tag)
    }

    func playPreview(_ file: URL, as tag: String) {
        let seconds = SongPreview.shared.play(file)
        guard seconds > 0 else { stopPreview(); return }
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((seconds + 0.15) * 1_000_000_000))
            guard !Task.isCancelled, let self, self.previewingVoice == tag else { return }
            self.stopPreview()
        }
    }

    public func stopPreview() {
        previewTask?.cancel(); previewTask = nil
        if previewingVoice != nil { SongPreview.shared.stop() }
        previewingVoice = nil
        voice.set(.previewing(nil))
    }

    // MARK: - Runs

    /// Narrates a built day in `selection` (a first voice, or another one).
    public func voice(_ slug: String, _ id: UUID, day: Int, selection: VoiceSelection, rescript: Bool = false) {
        guard voiceKey != nil else { config.set(.problem("\(ElevenLabsError.noKey)")); return }
        let key = RunKey.voice(id, day)
        watch(generation.center.$voicer.events(key: key), slug: slug, id: id)
        generation.center.voicer.send(Voicer.Input(projectSlug: slug, campaignID: id, dayIndex: day, task: .english(selection, rescript: rescript)))
    }

    /// Narration on or off for a campaign's builds from now on: the voice its brief carries.
    /// Returns the campaign as written, or nil when it could not be.
    @discardableResult
    public func setCampaignVoice(_ slug: String, _ id: UUID, _ selection: VoiceSelection?) async -> Campaign? {
        guard let paths = paths(slug, id) else { return nil }
        do {
            let campaign = try await CampaignLedger.shared.update(paths) { $0.brief.voiceOver = selection }
            campaigns.set(.updated(slug: slug, campaign))
            if let selection {
                update { $0.voiceID = selection.voiceID; $0.voiceName = selection.voiceName; $0.voiceModel = selection.modelID }
                config.set(.notice("\(campaign.name) is narrated by \(selection.voiceName): every build from now on gets the voice."))
            } else {
                config.set(.notice("\(campaign.name)'s new builds stay silent; days already narrated keep their voice."))
            }
            return campaign
        } catch {
            config.set(.problem("\(error)"))
            return nil
        }
    }

    /// The campaign's built days that have no voice yet, narrated in its voice. A day something is
    /// working on is left alone.
    public func voiceBuiltDays(_ slug: String, _ campaign: Campaign) {
        guard let selection = campaign.brief.voiceOver else { config.set(.notice("Turn voice-over on for this campaign first.")); return }
        guard voiceKey != nil else { config.set(.problem("\(ElevenLabsError.noKey)")); return }
        let days = campaign.silentBuiltDays.filter { generation.state.dayRun(campaign.id, $0)?.phase != .running }
        guard !days.isEmpty else { config.set(.notice("Every built day already has a voice.")); return }
        for day in days { voice(slug, campaign.id, day: day, selection: selection) }
        config.set(.notice("Narrating \(days.count) built \(days.count == 1 ? "day" : "days") with \(selection.voiceName), two at a time."))
    }

    /// The day's confirmed English in other languages.
    public func languages(_ slug: String, _ id: UUID, day: Int, _ languages: [Language]) {
        guard voiceKey != nil else { config.set(.problem("\(ElevenLabsError.noKey)")); return }
        let targets = languages.filter { $0 != .english }.sorted()
        guard !targets.isEmpty else { return }
        let key = RunKey.voice(id, day)
        watch(generation.center.$voicer.events(key: key), slug: slug, id: id)
        generation.center.voicer.send(Voicer.Input(projectSlug: slug, campaignID: id, dayIndex: day, task: .languages(targets)))
    }

    /// The person has listened to the day's English and says it is right.
    public func confirmEnglish(_ slug: String, _ id: UUID, day: Int) async {
        guard let paths = paths(slug, id) else { return }
        do {
            let campaign = try await CampaignLedger.shared.updateDay(paths, index: day) { d in
                if d.asset?.voiceOver != nil { d.asset?.voiceOver?.confirmedAt = Date() }
            }
            campaigns.set(.updated(slug: slug, campaign))
            config.set(.notice("English confirmed. Choose the languages and generate them."))
        } catch {
            config.set(.problem("\(error)"))
        }
    }

    /// Every day whose English is confirmed, in the saved languages it does not have yet.
    public func voiceAllConfirmed(_ slug: String, _ id: UUID) {
        let wanted = settings.voiceLanguages
        guard !wanted.isEmpty else { config.set(.notice("Choose the languages in Settings › Voice first.")); return }
        guard let campaign = campaigns.state.campaign(id) else { return }
        var sent = 0
        for day in campaign.days {
            guard let vo = day.asset?.voiceOver, vo.isConfirmed else { continue }
            let missing = wanted.filter { !(vo.track($0)?.isFresh ?? false) }
            guard !missing.isEmpty else { continue }
            languages(slug, id, day: day.index, missing)
            sent += 1
        }
        config.set(.notice(sent == 0 ? "Every confirmed day already has its languages." : "Voicing \(sent) \(sent == 1 ? "day" : "days") in \(wanted.map(\.title).joined(separator: ", "))."))
    }
}
