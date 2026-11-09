//
//  AdverbRuntimeRoot+Voice.swift
//  AdverbRuntime
//
//  WHAT: The voice-over's actions: the voices on this Mac and their previews, narrating a day,
//        confirming its English, and making its languages.
//  PIN:  A voice is optional and never gates the app. A preview is one sentence spoken by the voice
//        on this Mac the first time it is asked for, kept in the caches folder and played from there.
//

import AdverbAgents
import AdverbCore
import AdverbRender
import AdverbVoice
import Foundation

extension AdverbRuntimeRoot {

    // MARK: - Voices

    /// A voice is on this Mac to speak with.
    public var hasVoice: Bool { !VoiceLibrary.shared.packs.isEmpty }

    /// The packs on this Mac and their voices, and which previews are already made.
    public func loadVoices() async {
        let packs = await Task.detached { VoiceLibrary.shared.packs }.value
        voice.set(.packs(packs))
        voice.set(.cachedAll(Self.cachedPreviews()))
    }

    static let previewSentence = "Notes in the margin of everything: highlight a line, and ask about it."

    static func previewFile(pack: String, voice: String) -> URL {
        AdverbHome.voices.appendingPathComponent(pack.replacingOccurrences(of: ":", with: "-"), isDirectory: true)
            .appendingPathComponent("\(voice).wav")
    }

    static func cachedPreviews() -> Swift.Set<String> {
        var tags = Swift.Set<String>()
        for pack in AtomicFile.contents(of: AdverbHome.voices) where AtomicFile.isDirectory(pack) {
            for file in AtomicFile.contents(of: pack) where file.pathExtension == "wav" {
                tags.insert("\(pack.lastPathComponent)/\(file.deletingPathExtension().lastPathComponent)")
            }
        }
        return tags
    }

    /// Plays a voice's preview (spoken on this Mac the first time), or stops it if it is playing.
    public func previewVoice(pack: String, voice id: String) async {
        let tag = "\(pack)/\(id)"
        if previewingVoice == tag { stopPreview(); return }
        stopPreview()
        let file = Self.previewFile(pack: pack, voice: id)
        if !FileManager.default.fileExists(atPath: file.path) {
            voice.set(.preparing(tag))
            defer { voice.set(.preparing(nil)) }
            do {
                let synthesizer = try await VoiceLibrary.shared.synthesizer(pack: pack)
                let clip = try await synthesizer.speak(SpeechRequest(text: Self.previewSentence, voiceID: id))
                try WAVFile.write(clip.samples, sampleRate: clip.sampleRate, to: file)
                voice.set(.cached(tag))
            } catch {
                config.set(.problem("The preview could not be spoken: \(error)"))
                return
            }
        }
        previewingVoice = tag
        voice.set(.previewing(tag))
        playPreview(file, as: tag)
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
        guard hasVoice else { config.set(.problem("\(SpeechError.noPack)")); return }
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
                update { $0.voiceID = selection.voiceID; $0.voiceName = selection.voiceName; $0.voicePack = selection.packID }
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
        guard hasVoice else { config.set(.problem("\(SpeechError.noPack)")); return }
        let days = campaign.silentBuiltDays.filter { generation.state.dayRun(campaign.id, $0)?.phase != .running }
        guard !days.isEmpty else { config.set(.notice("Every built day already has a voice.")); return }
        for day in days { voice(slug, campaign.id, day: day, selection: selection) }
        config.set(.notice("Narrating \(days.count) built \(days.count == 1 ? "day" : "days") with \(selection.voiceName), two at a time."))
    }

    /// The day's confirmed English in other languages.
    public func languages(_ slug: String, _ id: UUID, day: Int, _ languages: [Language]) {
        guard hasVoice else { config.set(.problem("\(SpeechError.noPack)")); return }
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
