//
//  ElevenLabsTypes.swift
//  AdverbCore
//
//  WHAT: ElevenLabs' wire shapes Adverb reads and sends: a voice (GET /v2/voices), the
//        subscription (GET /v1/user), a speech request and its answer with timings
//        (POST /v1/text-to-speech/{voice}/with-timestamps), and the error.
//  PIN:  snake_case on the wire, spelled out in CodingKeys. Decoding is tolerant where ElevenLabs
//        adds fields freely (a voice's labels, its languages): a voice missing one still lists.
//

import Foundation

/// A voice as the picker shows it.
public struct ElevenVoice: Codable, Sendable, Equatable, Hashable, Identifiable {
    public struct VerifiedLanguage: Codable, Sendable, Equatable, Hashable {
        public var language: String
        public var modelID: String?
        public var accent: String?
        public var locale: String?
        public var previewURL: URL?

        enum CodingKeys: String, CodingKey {
            case language, accent, locale
            case modelID = "model_id"
            case previewURL = "preview_url"
        }
    }

    public var id: String
    public var name: String
    public var category: String?
    public var description: String?
    public var labels: [String: String]
    public var previewURL: URL?
    public var verifiedLanguages: [VerifiedLanguage]
    public var settings: VoiceSettings?

    public init(id: String, name: String, category: String? = nil, description: String? = nil, labels: [String: String] = [:],
                previewURL: URL? = nil, verifiedLanguages: [VerifiedLanguage] = [], settings: VoiceSettings? = nil) {
        self.id = id; self.name = name; self.category = category; self.description = description; self.labels = labels
        self.previewURL = previewURL; self.verifiedLanguages = verifiedLanguages; self.settings = settings
    }

    enum CodingKeys: String, CodingKey {
        case id = "voice_id"
        case name, category, description, labels, settings
        case previewURL = "preview_url"
        case verifiedLanguages = "verified_languages"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? id
        category = try? c.decode(String.self, forKey: .category)
        description = try? c.decode(String.self, forKey: .description)
        labels = (try? c.decode([String: String].self, forKey: .labels)) ?? [:]
        previewURL = (try? c.decode(String.self, forKey: .previewURL)).flatMap(URL.init(string:))
        verifiedLanguages = (try? c.decode([VerifiedLanguage].self, forKey: .verifiedLanguages)) ?? []
        settings = try? c.decode(VoiceSettings.self, forKey: .settings)
    }

    /// "female · american · young · narration": the labels a person picks a voice by.
    public var summary: String {
        ["gender", "accent", "age", "use_case", "descriptive"].compactMap { labels[$0]?.replacingOccurrences(of: "_", with: " ") }
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return ([name, description ?? "", category ?? ""] + Array(labels.values)).contains { $0.lowercased().contains(q) }
    }
}

public struct ElevenVoicesPage: Decodable, Sendable {
    public var voices: [ElevenVoice]
    public var hasMore: Bool
    public var nextPageToken: String?

    enum CodingKeys: String, CodingKey {
        case voices
        case hasMore = "has_more"
        case nextPageToken = "next_page_token"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A voice that does not decode (no id) is skipped, not the page.
        voices = ((try? c.decode([Lenient<ElevenVoice>].self, forKey: .voices)) ?? []).compactMap(\.value)
        hasMore = (try? c.decode(Bool.self, forKey: .hasMore)) ?? false
        nextPageToken = try? c.decode(String.self, forKey: .nextPageToken)
    }
}

/// Decodes a T or nothing: one bad element does not sink the array.
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

public struct ElevenUser: Decodable, Sendable {
    public struct Subscription: Decodable, Sendable {
        public var tier: String?
        public var characterCount: Int
        public var characterLimit: Int
        public var nextCharacterCountResetUnix: Int?
        public var status: String?

        enum CodingKeys: String, CodingKey {
            case tier, status
            case characterCount = "character_count"
            case characterLimit = "character_limit"
            case nextCharacterCountResetUnix = "next_character_count_reset_unix"
        }
    }

    public var subscription: Subscription

    public var quota: VoiceQuota {
        VoiceQuota(used: subscription.characterCount, limit: subscription.characterLimit,
                   resetsAt: subscription.nextCharacterCountResetUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                   tier: subscription.tier)
    }
}

/// When each character was spoken, relative to the clip.
public struct TTSAlignment: Codable, Sendable, Equatable {
    public var characters: [String]
    public var starts: [Double]
    public var ends: [Double]

    public init(characters: [String], starts: [Double], ends: [Double]) {
        self.characters = characters; self.starts = starts; self.ends = ends
    }

    enum CodingKeys: String, CodingKey {
        case characters
        case starts = "character_start_times_seconds"
        case ends = "character_end_times_seconds"
    }

    /// From the first spoken character to the last (whitespace is not speech).
    public var spokenSpan: (start: Double, end: Double)? {
        let n = min(characters.count, starts.count, ends.count)
        let spoken = (0..<n).filter { !characters[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let first = spoken.first, let last = spoken.last else { return nil }
        return (starts[first], ends[last])
    }

    /// Runs of non-whitespace characters, with the span each was spoken in.
    public var words: [WordTiming] {
        let n = min(characters.count, starts.count, ends.count)
        var out: [WordTiming] = []
        var text = "", start = 0.0, end = 0.0
        for i in 0..<n {
            let ch = characters[i]
            if ch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !text.isEmpty { out.append(WordTiming(text: text, start: start, end: end)); text = "" }
            } else {
                if text.isEmpty { start = starts[i] }
                text += ch; end = ends[i]
            }
        }
        if !text.isEmpty { out.append(WordTiming(text: text, start: start, end: end)) }
        return out
    }
}

public struct TTSResponse: Decodable, Sendable {
    public var audioBase64: String
    public var alignment: TTSAlignment?
    public var normalizedAlignment: TTSAlignment?

    enum CodingKeys: String, CodingKey {
        case audioBase64 = "audio_base64"
        case alignment
        case normalizedAlignment = "normalized_alignment"
    }
}

/// One line spoken: the audio and when its words fell.
public struct TTSResult: Sendable, Equatable {
    public var audio: Data
    public var alignment: TTSAlignment?
    public var requestID: String?
    public var characters: Int

    public init(audio: Data, alignment: TTSAlignment?, requestID: String?, characters: Int) {
        self.audio = audio; self.alignment = alignment; self.requestID = requestID; self.characters = characters
    }
}

public struct TTSRequest: Sendable, Equatable {
    public var voiceID: String
    public var text: String
    public var modelID: String
    /// ISO 639-1; sent only to models that take it (not Multilingual v2).
    public var languageCode: String?
    public var settings: VoiceSettings?
    public var previousText: String?
    public var nextText: String?
    /// Up to three: the request ids of the lines before, so the voice carries on as one read.
    public var previousRequestIDs: [String]
    public var seed: Int?
    public var outputFormat: String

    public init(voiceID: String, text: String, modelID: String = VoiceSelection.defaultModel, languageCode: String? = nil,
                settings: VoiceSettings? = nil, previousText: String? = nil, nextText: String? = nil, previousRequestIDs: [String] = [],
                seed: Int? = nil, outputFormat: String = "mp3_44100_128") {
        self.voiceID = voiceID; self.text = text; self.modelID = modelID; self.languageCode = languageCode
        self.settings = settings; self.previousText = previousText; self.nextText = nextText
        self.previousRequestIDs = previousRequestIDs; self.seed = seed; self.outputFormat = outputFormat
    }
}

public enum ElevenLabsModel {
    /// Multilingual v2 rejects `language_code`; the newer models take it.
    public static func acceptsLanguageCode(_ id: String) -> Bool { !id.hasPrefix("eleven_multilingual") }

    /// Characters one request may carry.
    public static func maxCharacters(_ id: String) -> Int {
        switch id {
        case "eleven_flash_v2_5": 40_000
        case "eleven_flash_v2": 30_000
        case "eleven_v3": 5_000
        default: 10_000
        }
    }
}

public enum ElevenLabsError: Error, Equatable, CustomStringConvertible {
    case noKey
    case http(Int, String)
    case decoding(String)
    case invalid(String)

    public var description: String {
        switch self {
        case .noKey: "No ElevenLabs key. Add one in Settings › Voice."
        case .http(401, let body) where Self.status(body) == "quota_exceeded":
            "ElevenLabs has no characters left this period: \(Self.message(body))"
        case .http(401, _): "The ElevenLabs key was refused (401). Check it in Settings › Voice."
        case .http(402, let body): "ElevenLabs needs a paid plan or more characters for this (402): \(Self.message(body))"
        case .http(429, _): "ElevenLabs rate limited the request (429). Adverb retried and gave up; try again in a minute."
        case .http(let code, let body): "ElevenLabs HTTP \(code): \(Self.message(body))"
        case .decoding(let message): "ElevenLabs answered in an unexpected shape: \(message)"
        case .invalid(let message): message
        }
    }

    /// ElevenLabs' own message: `detail.message`, else `detail` as text, else the body clipped.
    public static func message(_ body: String) -> String {
        if let json = try? JSONValue.parse(body) {
            if let message = json.value(at: "detail.message")?.stringValue { return message }
            if let detail = json.value(at: "detail")?.stringValue { return detail }
        }
        return String(body.prefix(300))
    }

    static func status(_ body: String) -> String? {
        (try? JSONValue.parse(body))?.value(at: "detail.status")?.stringValue
    }

    public var isRetryable: Bool {
        if case .http(let code, _) = self { return code == 408 || code == 429 || code >= 500 }
        return false
    }
}
