import Foundation
import Testing
@testable import AdverbAgents
@testable import AdverbCore

@Suite struct VoiceSynthTests {
    let rachel = VoiceSelection(voiceID: "rachel", voiceName: "Rachel")

    @Test func aClipIsKeyedByWhatMakesItSound() {
        let base = VoiceSynth.cacheKey(text: "Hello.", selection: rachel, language: .english, speed: 1)
        #expect(base == VoiceSynth.cacheKey(text: "Hello.", selection: rachel, language: .english, speed: 1))
        #expect(base != VoiceSynth.cacheKey(text: "Hello!", selection: rachel, language: .english, speed: 1))
        #expect(base != VoiceSynth.cacheKey(text: "Hello.", selection: VoiceSelection(voiceID: "adam", voiceName: "Adam"), language: .english, speed: 1))
        #expect(base != VoiceSynth.cacheKey(text: "Hello.", selection: rachel, language: .german, speed: 1))
        #expect(base != VoiceSynth.cacheKey(text: "Hello.", selection: rachel, language: .english, speed: 1.1))
        var steadier = rachel; steadier.settings.stability = 0.8
        #expect(base != VoiceSynth.cacheKey(text: "Hello.", selection: steadier, language: .english, speed: 1))
    }

    @Test func aLongLineIsAskedForFasterUpToTheCap() {
        #expect(VoiceSynth.fitSpeed(spoken: 2.0, allowed: 2.5, speed: 1) == 1)
        // 2.2 s for 2.0 s: about 1.1 × 1.02, rounded up to the hundredth.
        #expect(VoiceSynth.fitSpeed(spoken: 2.2, allowed: 2.0, speed: 1) == 1.13)
        #expect(VoiceSynth.fitSpeed(spoken: 4.0, allowed: 2.0, speed: 1) == 1.15)
        #expect(VoiceSynth.fitSpeed(spoken: 2.1, allowed: 2.0, speed: 1.15) == 1.15)
    }

    @Test func stepsAreSaidOnce() {
        let box = EventBox()
        let tell = StepTeller { box.add($0) }
        tell("Mixing the voice-over", 0)
        tell("Mixing the voice-over", 0.5)
        tell("Captions", 0)
        #expect(box.events.filter { if case .step = $0 { return true }; return false } == [.step("Mixing the voice-over"), .step("Captions")])
        #expect(box.events.contains(.progress(0.5)))
    }
}

final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [GenerationEvent] = []
    func add(_ e: GenerationEvent) { lock.withLock { list.append(e) } }
    var events: [GenerationEvent] { lock.withLock { list } }
}
