//
//  ElevenLabsClient.swift
//  AdverbCore
//
//  WHAT: ElevenLabs over URLSession: the voices, the subscription (the key's free check), and one
//        line of speech with its character timings.
//  PIN:  The key goes in `xi-api-key`. Speech is mp3 at 44.1 kHz/128 kbps, which every tier may
//        ask for; AVFoundation decodes it. Retries back off 2, 8 and 20 s on 408/429/5xx and on a
//        dropped connection, as the Claude client does.
//

import Foundation

public struct ElevenLabsConfig: Sendable, Equatable {
    public var apiKey: Secret
    public var baseURL: URL
    public var timeout: TimeInterval

    public init(apiKey: Secret, baseURL: URL = URL(string: "https://api.elevenlabs.io")!, timeout: TimeInterval = 120) {
        self.apiKey = apiKey; self.baseURL = baseURL; self.timeout = timeout
    }
}

public struct ElevenLabsClient: Sendable {
    public let config: ElevenLabsConfig
    let session: URLSession

    public init(config: ElevenLabsConfig, session: URLSession = .shared) {
        self.config = config; self.session = session
    }

    // MARK: - Requests (public so their shape is tested)

    public func body(_ r: TTSRequest) -> JSONValue {
        var body: [String: JSONValue] = ["text": .string(r.text), "model_id": .string(r.modelID)]
        if let code = r.languageCode, ElevenLabsModel.acceptsLanguageCode(r.modelID) { body["language_code"] = .string(code) }
        if let s = r.settings {
            body["voice_settings"] = .object([
                "stability": .number(s.stability), "similarity_boost": .number(s.similarityBoost), "style": .number(s.style),
                "use_speaker_boost": .bool(s.useSpeakerBoost), "speed": .number(s.speed),
            ])
        }
        if let previous = r.previousText, !previous.isEmpty { body["previous_text"] = .string(previous) }
        if let next = r.nextText, !next.isEmpty { body["next_text"] = .string(next) }
        if !r.previousRequestIDs.isEmpty { body["previous_request_ids"] = .array(r.previousRequestIDs.suffix(3).map { .string($0) }) }
        if let seed = r.seed { body["seed"] = .number(Double(seed)) }
        return .object(body)
    }

    public func urlRequest(_ r: TTSRequest) throws -> URLRequest {
        var components = URLComponents(url: config.baseURL.appendingPathComponent("v1/text-to-speech/\(r.voiceID)/with-timestamps"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "output_format", value: r.outputFormat)]
        var request = authorized(components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try body(r).data()
        return request
    }

    public func voicesRequest(pageToken: String? = nil) -> URLRequest {
        var components = URLComponents(url: config.baseURL.appendingPathComponent("v2/voices"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "page_size", value: "100"), URLQueryItem(name: "include_total_count", value: "false")]
            + (pageToken.map { [URLQueryItem(name: "next_page_token", value: $0)] } ?? [])
        return authorized(components.url!)
    }

    public func userRequest() -> URLRequest { authorized(config.baseURL.appendingPathComponent("v1/user")) }

    func authorized(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue(config.apiKey.value, forHTTPHeaderField: "xi-api-key")
        r.setValue("application/json", forHTTPHeaderField: "accept")
        r.timeoutInterval = config.timeout
        return r
    }

    // MARK: - Calls

    /// One line spoken, with when each character fell.
    public func speak(_ r: TTSRequest) async throws -> TTSResult {
        let request = try urlRequest(r)
        let (data, response) = try await withRetries { try await self.send(request) }
        return try Self.result(data, requestID: response.value(forHTTPHeaderField: "request-id"), characters: r.text.count)
    }

    /// Every voice the key can use: the account's own and the defaults, page by page.
    public func voices() async throws -> [ElevenVoice] {
        var all: [ElevenVoice] = []
        var token: String?
        for _ in 0..<20 {
            let request = voicesRequest(pageToken: token)
            let (data, _) = try await withRetries { try await self.send(request) }
            let page: ElevenVoicesPage
            do { page = try JSONDecoder().decode(ElevenVoicesPage.self, from: data) } catch { throw ElevenLabsError.decoding("\(error)") }
            all += page.voices
            guard page.hasMore, let next = page.nextPageToken, !next.isEmpty else { break }
            token = next
        }
        var seen = Set<String>()
        return all.filter { seen.insert($0.id).inserted }
    }

    /// Where the subscription stands. Free: the key's check.
    public func user() async throws -> VoiceQuota {
        let request = userRequest()
        let (data, _) = try await withRetries { try await self.send(request) }
        do { return try JSONDecoder().decode(ElevenUser.self, from: data).quota } catch { throw ElevenLabsError.decoding("\(error)") }
    }

    @discardableResult
    public func ping() async throws -> VoiceQuota { try await user() }

    // MARK: - Parsing and transport

    public static func result(_ data: Data, requestID: String?, characters: Int) throws -> TTSResult {
        let decoded: TTSResponse
        do { decoded = try JSONDecoder().decode(TTSResponse.self, from: data) } catch { throw ElevenLabsError.decoding("\(error)") }
        guard let audio = Data(base64Encoded: decoded.audioBase64), !audio.isEmpty else { throw ElevenLabsError.decoding("no audio in the answer") }
        return TTSResult(audio: audio, alignment: decoded.alignment ?? decoded.normalizedAlignment, requestID: requestID, characters: characters)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ElevenLabsError.invalid("No HTTP response from ElevenLabs.") }
        guard (200..<300).contains(http.statusCode) else { throw ElevenLabsError.http(http.statusCode, String(decoding: data, as: UTF8.self)) }
        return (data, http)
    }

    func withRetries<T: Sendable>(_ attempt: @Sendable () async throws -> T) async throws -> T {
        let delays: [UInt64] = [2, 8, 20]
        var last: Error = ElevenLabsError.invalid("no attempt")
        for i in 0...delays.count {
            do { return try await attempt() } catch let error as ElevenLabsError where error.isRetryable && i < delays.count {
                last = error
                try await Task.sleep(nanoseconds: delays[i] * 1_000_000_000)
            } catch let error as URLError where i < delays.count && error.code != .cancelled {
                last = error
                try await Task.sleep(nanoseconds: delays[i] * 1_000_000_000)
            }
        }
        throw last
    }
}
