import Foundation
import Testing
@testable import AdverbCore

@Suite struct ElevenLabsTests {
    let client = ElevenLabsClient(config: ElevenLabsConfig(apiKey: Secret("xi-test-key")!))

    @Test func speechRequestHasTheCurrentShape() throws {
        let tts = TTSRequest(voiceID: "v1", text: "Hello.", modelID: "eleven_multilingual_v2", languageCode: "en",
                             settings: VoiceSettings(speed: 1.1), previousText: "Before.", nextText: "", previousRequestIDs: ["a", "b", "c", "d"], seed: 7)
        let r = try client.urlRequest(tts)
        #expect(r.httpMethod == "POST")
        #expect(r.url?.absoluteString == "https://api.elevenlabs.io/v1/text-to-speech/v1/with-timestamps?output_format=mp3_44100_128")
        #expect(r.value(forHTTPHeaderField: "xi-api-key") == "xi-test-key")
        let body = client.body(tts)
        #expect(body["text"]?.stringValue == "Hello.")
        #expect(body["model_id"]?.stringValue == "eleven_multilingual_v2")
        // Multilingual v2 rejects language_code; empty context is not sent; at most three ids.
        #expect(body["language_code"] == nil)
        #expect(body["next_text"] == nil)
        #expect(body["previous_text"]?.stringValue == "Before.")
        #expect(body["previous_request_ids"]?.arrayValue?.compactMap(\.stringValue) == ["b", "c", "d"])
        #expect(body["voice_settings"]?["speed"]?.doubleValue == 1.1)
        #expect(body["voice_settings"]?["similarity_boost"]?.doubleValue == 0.75)
        var flash = tts; flash.modelID = "eleven_flash_v2_5"; flash.languageCode = "de"
        #expect(client.body(flash)["language_code"]?.stringValue == "de")
    }

    @Test func voicesAndUserRequests() {
        let first = client.voicesRequest()
        #expect(first.url?.path == "/v2/voices")
        #expect(first.url?.query?.contains("page_size=100") == true)
        #expect(client.voicesRequest(pageToken: "t2").url?.query?.contains("next_page_token=t2") == true)
        #expect(client.userRequest().url?.absoluteString == "https://api.elevenlabs.io/v1/user")
        #expect(client.userRequest().value(forHTTPHeaderField: "xi-api-key") == "xi-test-key")
    }

    @Test func parsesASpeechAnswerWithTimings() throws {
        let data = try Data(contentsOf: Fixture.url("elevenlabs/with-timestamps.json"))
        let result = try ElevenLabsClient.result(data, requestID: "req-1", characters: 10)
        #expect(String(decoding: result.audio, as: UTF8.self) == "ID3fake-mp3-bytes")
        #expect(result.requestID == "req-1")
        let alignment = try #require(result.alignment)
        // The leading space is not speech.
        #expect(alignment.spokenSpan?.start == 0.05)
        #expect(alignment.spokenSpan?.end == 0.7)
        #expect(alignment.words.map(\.text) == ["Hi", "there."])
        #expect(alignment.words[1].start == 0.26)
    }

    @Test func parsesVoicesAndTheSubscription() throws {
        let page = try JSONDecoder().decode(ElevenVoicesPage.self, from: Data(contentsOf: Fixture.url("elevenlabs/voices.json")))
        #expect(page.voices.map(\.name) == ["Rachel", "Adam"])
        let rachel = page.voices[0]
        #expect(rachel.id == "21m00Tcm4TlvDq8ikWAM")
        #expect(rachel.summary == "female · american · young · narration")
        #expect(rachel.previewURL?.lastPathComponent == "preview.mp3")
        #expect(rachel.settings?.similarityBoost == 0.75)
        #expect(rachel.matches("NARRAT"))
        #expect(!rachel.matches("british"))
        #expect(page.voices[1].labels.isEmpty)
        let quota = try JSONDecoder().decode(ElevenUser.self, from: Data(contentsOf: Fixture.url("elevenlabs/user.json"))).quota
        #expect(quota.used == 12_340 && quota.limit == 100_000 && quota.remaining == 87_660)
        #expect(quota.resetsAt == Date(timeIntervalSince1970: 1_793_836_800))
        #expect(quota.tier == "creator")
    }

    @Test func errorsSayWhatHappened() {
        #expect(ElevenLabsError.http(401, #"{"detail":{"status":"invalid_api_key","message":"Invalid API key"}}"#).description.contains("refused"))
        #expect(ElevenLabsError.http(401, #"{"detail":{"status":"quota_exceeded","message":"You have 3 credits left."}}"#).description.contains("no characters left"))
        #expect(ElevenLabsError.http(422, #"{"detail":"voice_id is not valid"}"#).description == "ElevenLabs HTTP 422: voice_id is not valid")
        #expect(ElevenLabsError.http(429, "").isRetryable)
        #expect(ElevenLabsError.http(503, "").isRetryable)
        #expect(!ElevenLabsError.http(400, "").isRetryable)
    }

    @Test func voiceUsageCosts() {
        let u = VoiceUsage(characters: 2_000, requests: 6, modelID: "eleven_multilingual_v2") + VoiceUsage(characters: 1_000, requests: 3, modelID: "eleven_multilingual_v2")
        #expect(u.characters == 3_000 && u.requests == 9)
        #expect(abs(u.estimatedUSD() - 0.30) < 1e-9)
        #expect(abs(VoiceUsage(characters: 1_000, modelID: "eleven_flash_v2_5").estimatedUSD() - 0.05) < 1e-9)
    }
}
