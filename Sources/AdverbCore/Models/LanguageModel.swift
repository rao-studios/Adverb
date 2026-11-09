//
//  LanguageModel.swift
//  AdverbCore
//
//  WHAT: The seam every written step goes through — the plan, a page, the stills review, a
//        voice-over, a translation, a re-time: a request (one system prompt, turns of text and
//        images, the format the answer must take) to a model on this Mac, and its answer.
//  PIN:  Nothing here names MLX. AdverbModels implements it (MLXLanguageModel); the agents see
//        only this, so a test hands them a fake and the probe any model on disk.
//  PIN:  A text part marked `stable` is the same bytes for every call of a campaign (the system
//        prompt, the frozen digest). A model that keeps its cache between calls pins a snapshot
//        where the stable parts end, so thirty pages read the skill and the project once.
//

import Foundation

/// What a model is, as the app and the logs name it.
public struct ModelInfo: Sendable, Equatable, Hashable {
    /// The repo id it was loaded as ("rao-studios/gemma-4-31b-it-mlx-4bit"), or a folder's name.
    public var id: String
    /// The commit its files were fetched at, when known.
    public var revision: String?
    public var title: String
    /// The longest prompt plus answer it is made for.
    public var contextTokens: Int
    /// It reads images (a vision model): the stills review can run on it.
    public var acceptsImages: Bool
    /// Its template can think before it answers (`enable_thinking`, `<think>`).
    public var thinks: Bool

    public init(id: String, revision: String? = nil, title: String? = nil, contextTokens: Int = 32_768,
                acceptsImages: Bool = false, thinks: Bool = false) {
        self.id = id; self.revision = revision; self.title = title ?? ModelInfo.shortName(id)
        self.contextTokens = contextTokens; self.acceptsImages = acceptsImages; self.thinks = thinks
    }

    /// "gemma-4-31b-it-mlx-4bit" from "rao-studios/gemma-4-31b-it-mlx-4bit".
    public static func shortName(_ id: String) -> String { id.split(separator: "/").last.map(String.init) ?? id }
}

public enum ModelRole: String, Sendable, Equatable, Hashable, Codable { case user, assistant }

public enum ModelPart: Sendable, Equatable, Hashable {
    /// Text; `stable` when it is the same for every call of the campaign (see the PIN above).
    case text(String, stable: Bool)
    /// A JPEG the model looks at (vision models only).
    case jpeg(Data)

    public static func text(_ text: String) -> ModelPart { .text(text, stable: false) }

    public var text: String? { if case .text(let t, _) = self { return t }; return nil }
    public var isImage: Bool { if case .jpeg = self { return true }; return false }
}

public struct ModelTurn: Sendable, Equatable, Hashable {
    public var role: ModelRole
    public var parts: [ModelPart]

    public init(role: ModelRole, parts: [ModelPart]) { self.role = role; self.parts = parts }

    public static func user(_ parts: [ModelPart]) -> ModelTurn { .init(role: .user, parts: parts) }
    public static func user(_ text: String) -> ModelTurn { .init(role: .user, parts: [.text(text)]) }
    public static func assistant(_ text: String) -> ModelTurn { .init(role: .assistant, parts: [.text(text)]) }

    /// The turn's text parts joined, images left out.
    public var text: String { parts.compactMap(\.text).joined(separator: "\n\n") }
    public var hasImages: Bool { parts.contains(where: \.isImage) }
}

public enum ThinkingMode: Sendable, Equatable, Hashable {
    case off
    /// Think first, for at most `budget` tokens; then the thinking is closed and the answer begins.
    case on(budget: Int)
}

public struct ModelRequest: Sendable, Equatable {
    public var system: String
    public var turns: [ModelTurn]
    public var format: AnswerFormat
    /// Tokens the answer may take, thinking included.
    public var maxTokens: Int
    /// Nil: the model's own (its generation_config.json), else a sensible default.
    public var temperature: Double?
    public var thinking: ThinkingMode
    /// What the call is for, for the log ("plan", "page", "review", "voice-over").
    public var label: String
    /// The answer begins with these characters, written for the model (it carries on from them);
    /// the answer's text includes them. A model that cannot be started this way ignores it.
    public var answerPrefix: String?

    public init(system: String, turns: [ModelTurn], format: AnswerFormat = .text, maxTokens: Int = 8_192,
                temperature: Double? = nil, thinking: ThinkingMode = .off, label: String = "", answerPrefix: String? = nil) {
        self.system = system; self.turns = turns; self.format = format; self.maxTokens = maxTokens
        self.temperature = temperature; self.thinking = thinking; self.label = label; self.answerPrefix = answerPrefix
    }

    public var hasImages: Bool { turns.contains(where: \.hasImages) }
}

public enum ModelEvent: Sendable, Equatable {
    /// What the model is thinking, as it thinks.
    case thinking(String)
    /// The answer, as it is written.
    case text(String)
    /// Where it is: "Reading 24,812 tokens (20,104 from the last call)".
    case status(String)
    /// The call so far.
    case usage(TokenUsage)
}

public struct ModelAnswer: Sendable, Equatable {
    /// The answer, the thinking taken out.
    public var text: String
    public var thinking: String
    public var usage: TokenUsage
    /// The model that answered (its id).
    public var model: String
    /// It stopped at `maxTokens`, not at its end.
    public var truncated: Bool

    public init(text: String, thinking: String = "", usage: TokenUsage = .init(), model: String = "", truncated: Bool = false) {
        self.text = text; self.thinking = thinking; self.usage = usage; self.model = model; self.truncated = truncated
    }
}

/// A model on this Mac that answers in text.
public protocol LanguageModel: Sendable {
    var info: ModelInfo { get }
    func complete(_ request: ModelRequest, onEvent: @escaping @Sendable (ModelEvent) -> Void) async throws -> ModelAnswer
}

public enum ModelError: Error, Equatable, CustomStringConvertible {
    /// No model is set up for this step.
    case noModel(String)
    case notInstalled(String)
    case loadFailed(String)
    /// The answer could not be read in the format asked for.
    case unreadable(String)
    case invalid(String)
    case unsupported(String)
    /// MLX's kernels are not beside the binary.
    case noMetal(String)

    public var description: String {
        switch self {
        case .noModel(let what): what
        case .notInstalled(let id): "\(ModelInfo.shortName(id)) is not on this Mac. Download it in Settings › Models."
        case .loadFailed(let why): "The model did not load: \(why)"
        case .unreadable(let why): "The answer could not be read: \(why)"
        case .invalid(let why): why
        case .unsupported(let why): why
        case .noMetal(let hint): "MLX cannot run: \(hint)"
        }
    }
}
