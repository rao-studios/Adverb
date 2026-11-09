import Foundation
import Testing
@testable import AdverbAgents
@testable import AdverbCore

@Suite struct VoiceSynthTests {
    let heart = VoiceSelection(voiceID: "af_heart", voiceName: "Heart", packID: "paradee-af-heart")

    @Test func aClipIsKeyedByWhatMakesItSound() {
        func key(_ text: String = "Hello.", selection: VoiceSelection? = nil, revision: String? = "r1", language: Language = .english, speed: Double = 1) -> String {
            VoiceSynth.cacheKey(text: text, selection: selection ?? heart, revision: revision, language: language, speed: speed)
        }
        let base = key()
        #expect(base == key())
        #expect(base != key("Hello!"))
        #expect(base != key(selection: VoiceSelection(voiceID: "am_adam", voiceName: "Adam", packID: "kokoro-82m-en")))
        #expect(base != key(selection: VoiceSelection(voiceID: "af_heart", voiceName: "Heart", packID: "kokoro-82m-en")), "the same voice in another pack")
        #expect(base != key(language: .german))
        #expect(base != key(speed: 1.1))
        #expect(base != key(revision: "r2"), "a pack published again is spoken again")
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
