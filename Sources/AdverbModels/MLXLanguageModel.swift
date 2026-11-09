//
//  MLXLanguageModel.swift
//  AdverbModels
//
//  WHAT: A model on this Mac, loaded with MLX (Frigate's mlx-swift-lm), answering AdverbCore's
//        ModelRequest: the chat template applied to the system prompt and the turns, the prompt
//        prefilled (only what the cache does not already hold), tokens decoded until the end of the
//        answer or `maxTokens`, thinking split from the answer and closed when its budget runs out.
//  IN:   A ModelContainer (LLM or VLM: a vision model answers text-only requests too).
//  OUT:  ModelAnswer; events as it goes (status, thinking, text, usage).
//  PIN:  PREFIX REUSE (Craft's MLXTextSession): the cache keeps the last prompt and answer; a new
//        prompt that shares a prefix appends to it, trims it, or rewinds to a snapshot. A hybrid
//        model's recurrent layers cannot be trimmed, so a snapshot is pinned where the request's
//        stable parts end (the system prompt and the digest): every call of a campaign rewinds
//        there and reads only its own request. Thirty pages read the skill and the project once.
//  PIN:  SLIDING WINDOWS (Gemma 4, Mistral 3 with a window): a RotatingKVCache cannot be trimmed once
//        it has wrapped, and every prompt here passes the window (1,024 tokens on Gemma 4), yet
//        Frigate's CheckpointedCache classifies a layer as trimmable once, when it is empty, and trims
//        it anyway: the write index went negative and the next prefill trapped (2026-11-08). So the
//        window layers are COPIED at the pin (`WindowCopy`, about 1.3 GB on Gemma 4 31B) and a rewind
//        returns exactly there and restores them; with no copy that fits, the call starts fresh.
//  PIN:  A request with images (the stills review) is prefilled whole in a cache of its own and
//        leaves the text cache as it was: image tokens are placed by the processor, not by prefix.
//  PIN:  One generation at a time in the process (GPULane), and one per model (the lock).
//  PIN:  A loop is stopped (`Self.isLooping`): the same stretch written over and over is a model
//        that will not end on its own, and it would otherwise run to `maxTokens` for nothing.
//

import AdverbCore
import Foundation
import FrigateParallel
import MLX
import MLXLMCommon
import MLXVLM
import CoreImage

public final class MLXLanguageModel: AdverbCore.LanguageModel, @unchecked Sendable {
    public let info: ModelInfo
    let container: ModelContainer
    let files: ModelFiles?
    let isVision: Bool

    private let lock = NSLock()
    /// The last text prompt and answer, kept for the next call to share (nil while a call runs).
    private var cache: CheckpointedCache?
    private var cachedTokens: [Int] = []
    /// The cache's sliding-window layers as they stood at the pin (nil when the model has none).
    private var windowCopy: WindowCopy?

    static let heartbeat: TimeInterval = 2
    /// Tokens the stable prefix's pin stops short of where two requests part (Craft's askMargin).
    static let pinMargin = 4

    init(container: ModelContainer, info: ModelInfo, files: ModelFiles?, isVision: Bool) {
        self.container = container; self.info = info; self.files = files; self.isVision = isVision
    }

    public func complete(_ request: ModelRequest, onEvent: @escaping @Sendable (ModelEvent) -> Void) async throws -> ModelAnswer {
        if request.hasImages, !isVision {
            throw ModelError.unsupported("\(info.title) cannot read images.")
        }
        let asked = Date()
        return try await GPULane.shared.run {
            let waited = Date().timeIntervalSince(asked)
            if waited > 1 { onEvent(.status(String(format: "Waited %.0f s for the GPU", waited))) }
            let task = Task.detached(priority: .userInitiated) { [self] in
                try await self.generate(request, onEvent: onEvent)
            }
            return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        }
    }

    /// Forget the cached prompt (a model switch, a test).
    public func reset() { lock.withLock { cache = nil; cachedTokens = []; windowCopy = nil } }

    // MARK: - Generation

    private func generate(_ request: ModelRequest, onEvent: @escaping @Sendable (ModelEvent) -> Void) async throws -> ModelAnswer {
        let tokenizer = await container.tokenizer
        let configuration = await container.configuration
        let model = await container.perform { context in UncheckedBox(context.model) }.value
        let parameters = self.parameters(request)
        let start = Date()

        var stop = configuration.eosTokenIds
        if let eos = tokenizer.eosTokenId { stop.insert(eos) }
        for token in configuration.extraEOSTokens { if let id = tokenizer.convertTokenToId(token) { stop.insert(id) } }
        if tokenizer.convertTokenToId("<|im_end|>") != nil {
            for token in ["<|im_end|>", "<|im_start|>", "<|endoftext|>"] { if let id = tokenizer.convertTokenToId(token) { stop.insert(id) } }
        }

        // The prompt, prefilled.
        var iterator: TokenIterator
        var kv: CheckpointedCache?
        var copy: WindowCopy?
        var promptTokens: [Int] = []
        var reused = 0
        var prefilled = 0
        var openTags: ThinkingSplitter.Tags?
        if request.hasImages {
            let input = try await prepareWithImages(request)
            let count = input.text.tokens.size
            onEvent(.status("Reading \(count.formatted()) tokens and \(request.turns.flatMap(\.parts).filter(\.isImage).count) image(s)"))
            iterator = try TokenIterator(input: input, model: model, cache: model.newCache(parameters: parameters), parameters: parameters)
            prefilled = count
        } else {
            var tokens = try render(request, tokenizer: tokenizer)
            openTags = Self.thinkingOpenAtEnd(tokens, tokenizer: tokenizer)
            let startsThinking = openTags != nil
            // The answer started for the model: it carries on from these characters.
            if let opening = request.answerPrefix, !opening.isEmpty, !startsThinking {
                tokens += tokenizer.encode(text: opening, addSpecialTokens: false)
            }
            promptTokens = tokens
            // The cache is this call's until the answer is done (GPULane runs one call at a time).
            let (existing, existingTokens, existingCopy) = lock.withLock { () -> (CheckpointedCache?, [Int], WindowCopy?) in
                defer { cache = nil; cachedTokens = []; windowCopy = nil }
                return (cache, cachedTokens, windowCopy)
            }
            var cacheNow = CheckpointedCache(layers: [])
            var prefix = 0
            var fresh = true
            if let existing {
                let common = Self.commonPrefix(existingTokens, tokens)
                let wanted = common == tokens.count ? max(0, common - 1) : common
                if wanted == existingTokens.count, existing.position == wanted {
                    // Appended to, nothing trimmed: a window layer is as good as it was.
                    cacheNow = existing; prefix = wanted; fresh = false; copy = existingCopy
                } else if !WindowCopy.hasWindows(existing.layers) {
                    if let position = existing.rewind(toAtMost: wanted) { cacheNow = existing; prefix = position; fresh = false }
                } else if let kept = existingCopy, kept.tokenCount <= wanted, kept.tokenCount <= existing.position,
                          existing.rewind(toAtMost: kept.tokenCount) == kept.tokenCount {
                    // The full-attention layers trimmed back to the pin; the window layers restored to it.
                    kept.restore(into: existing.layers)
                    cacheNow = existing; prefix = kept.tokenCount; fresh = false; copy = kept
                }
            }
            if fresh { cacheNow = CheckpointedCache(layers: model.newCache(parameters: parameters)) }
            reused = prefix
            prefilled = tokens.count - prefix
            onEvent(.status(prefix > 0
                ? "Reading \(prefilled.formatted()) tokens (\(prefix.formatted()) already read)"
                : "Reading \(tokens.count.formatted()) tokens"))
            var rest = Array(tokens[prefix...])
            // Pin where the stable parts end, so the next call of the campaign rewinds there.
            if let pin = try stablePrefix(request, tokenizer: tokenizer), pin > prefix + 64, pin < tokens.count {
                _ = try TokenIterator(input: LMInput(tokens: MLXArray(Array(tokens[prefix..<pin]))), model: model, cache: cacheNow.layers,
                                      parameters: parameters)
                cacheNow.snapshot(at: pin, pinned: true)
                copy = WindowCopy.take(cacheNow.layers, at: pin)
                rest = Array(tokens[pin...])
            }
            iterator = try TokenIterator(input: LMInput(tokens: MLXArray(rest)), model: model, cache: cacheNow.layers, parameters: parameters)
            cacheNow.snapshot(at: tokens.count)
            kv = cacheNow
        }
        // The answer (begun with the opening the prompt carried, when it carried one).
        var detokenizer = NaiveStreamingDetokenizer(tokenizer: tokenizer)
        var splitter = ThinkingSplitter(startsThinking: openTags != nil, tags: openTags ?? ThinkingSplitter.qwen)
        let opening = !request.hasImages && openTags == nil ? (request.answerPrefix ?? "") : ""
        var thinkingText = "", answerText = opening
        if !opening.isEmpty { onEvent(.text(opening)) }
        var generated: [Int] = []
        var thinkingTokens = 0
        var closedByBudget = false
        var hitStop = false
        var looped = false
        var lastBeat = Date()

        func emit(_ pieces: [ThinkingSplitter.Piece]) {
            for piece in pieces {
                switch piece {
                case .thinking(let t): thinkingText += t; onEvent(.thinking(t))
                case .text(let t): answerText += t; onEvent(.text(t))
                }
            }
        }
        func usage() -> TokenUsage {
            TokenUsage(input: prefilled, output: generated.count, cacheRead: reused, seconds: Date().timeIntervalSince(start))
        }

        decode: while true {
            while let token = iterator.next() {
                if Task.isCancelled { throw CancellationError() }
                if stop.contains(token) { hitStop = true; break }
                generated.append(token)
                if generated.count % 128 == 0, Self.isLooping(generated) { looped = true; break }
                let wasThinking = splitter.isThinking
                detokenizer.append(token: token)
                if let text = detokenizer.next() { emit(splitter.feed(text)) }
                if wasThinking || splitter.isThinking { thinkingTokens += 1 }
                let now = Date()
                if now.timeIntervalSince(lastBeat) >= Self.heartbeat { onEvent(.usage(usage())); lastBeat = now }
                if case .on(let budget) = request.thinking, splitter.isThinking, thinkingTokens >= budget, !closedByBudget, let kv {
                    // Out of thinking: the tag is closed on the cache the thinking left, and the answer begins.
                    closedByBudget = true
                    let close = tokenizer.encode(text: "\n" + splitter.tags.close + "\n\n", addSpecialTokens: false)
                    for id in close { detokenizer.append(token: id) }
                    if let text = detokenizer.next() { emit(splitter.feed(text)) }
                    generated += close
                    var more = parameters
                    more.maxTokens = max(1, request.maxTokens - generated.count)
                    iterator = try TokenIterator(input: LMInput(tokens: MLXArray(close)), model: model, cache: kv.layers, parameters: more)
                    continue decode
                }
            }
            break
        }
        emit(splitter.finish())

        if let kv {
            lock.withLock {
                cachedTokens = promptTokens + generated
                cache = kv
                windowCopy = copy
            }
        }
        let total = usage()
        onEvent(.usage(total))
        if looped { onEvent(.status("Stopped a loop after \(generated.count.formatted()) tokens")) }
        return ModelAnswer(text: Self.cleaned(answerText), thinking: thinkingText.trimmingCharacters(in: .whitespacesAndNewlines),
                           usage: total, model: info.id, truncated: looped || (!hitStop && generated.count >= request.maxTokens))
    }

    // MARK: - Prompt

    /// Sampling: the request's temperature, else the model's own, held to what writes careful code
    /// (Qwen's guidance: 0.6 and top-p 0.95 while thinking, its precise-coding preset; 0.7 and top-p
    /// 0.8 without). A generation_config.json's 1.0 is for open-ended chat, not a page of script.
    func parameters(_ request: ModelRequest) -> GenerateParameters {
        let thinking = request.thinking != .off
        let ceiling = thinking ? 0.6 : 0.7
        let temperature = request.temperature ?? min(files?.temperature ?? ceiling, ceiling)
        let topP = min(files?.topP ?? 0.95, thinking ? 0.95 : 0.8)
        return GenerateParameters(maxTokens: request.maxTokens, temperature: Float(temperature), topP: Float(topP),
                                  topK: files?.topK ?? 20, minP: 0)
    }

    /// The template's variables: thinking on or off, when the template takes the switch.
    func context(_ request: ModelRequest) -> [String: any Sendable]? {
        guard files?.takesThinkingSwitch == true else { return nil }
        if case .on = request.thinking { return ["enable_thinking": true] }
        return ["enable_thinking": false]
    }

    func messages(_ request: ModelRequest, replacingVariable variable: String? = nil) -> [[String: any Sendable]] {
        var out: [[String: any Sendable]] = [["role": "system", "content": request.system]]
        var lastStable: (turn: Int, part: Int)?
        for (t, turn) in request.turns.enumerated() {
            for (p, part) in turn.parts.enumerated() { if case .text(_, true) = part { lastStable = (t, p) } }
        }
        for (t, turn) in request.turns.enumerated() {
            if let variable, let lastStable {
                if t > lastStable.turn { break }
                if t == lastStable.turn {
                    let kept = turn.parts.prefix(lastStable.part + 1).compactMap(\.text)
                    out.append(["role": turn.role.rawValue, "content": (kept + [variable]).joined(separator: "\n\n")])
                    break
                }
            }
            out.append(["role": turn.role.rawValue, "content": turn.text])
        }
        return out
    }

    func render(_ request: ModelRequest, tokenizer: any Tokenizer, replacingVariable variable: String? = nil) throws -> [Int] {
        let dictionaries = messages(request, replacingVariable: variable)
        do {
            return try tokenizer.applyChatTemplate(messages: dictionaries, tools: nil, additionalContext: context(request))
        } catch {
            return try tokenizer.applyChatTemplate(messages: Self.mergedSystem(dictionaries), tools: nil, additionalContext: context(request))
        }
    }

    /// Where the request's stable parts end, in tokens: what two renders with different variable
    /// text agree on, less a margin. Nil when nothing is stable or the stable part is short.
    func stablePrefix(_ request: ModelRequest, tokenizer: any Tokenizer) throws -> Int? {
        guard request.turns.contains(where: { $0.parts.contains { if case .text(_, true) = $0 { return true }; return false } }) else { return nil }
        let one = try render(request, tokenizer: tokenizer, replacingVariable: "a")
        let other = try render(request, tokenizer: tokenizer, replacingVariable: "b")
        let shared = Self.commonPrefix(one, other) - Self.pinMargin
        return shared > 1_024 ? shared : nil
    }

    func prepareWithImages(_ request: ModelRequest) async throws -> LMInput {
        var chat: [Chat.Message] = [.system(request.system)]
        for turn in request.turns {
            let images = turn.parts.compactMap { part -> UserInput.Image? in
                guard case .jpeg(let data) = part, let image = CIImage(data: data) else { return nil }
                return .ciImage(image)
            }
            chat.append(turn.role == .user ? .user(turn.text, images: images) : .assistant(turn.text))
        }
        let input = UserInput(chat: chat, additionalContext: context(request))
        return try await container.prepare(input: input)
    }

    /// The thinking block the prompt ends inside (the template opened it for the model), if any.
    static func thinkingOpenAtEnd(_ tokens: [Int], tokenizer: any Tokenizer) -> ThinkingSplitter.Tags? {
        ThinkingSplitter.openAtEnd(of: tokenizer.decode(tokenIds: Array(tokens.suffix(12))))
    }

    static func mergedSystem(_ dictionaries: [[String: any Sendable]]) -> [[String: any Sendable]] {
        guard let first = dictionaries.first, first["role"] as? String == "system" else { return dictionaries }
        var rest = Array(dictionaries.dropFirst())
        let system = first["content"] as? String ?? ""
        if let index = rest.firstIndex(where: { $0["role"] as? String == "user" }) {
            rest[index]["content"] = system + "\n\n" + ((rest[index]["content"] as? String) ?? "")
        } else {
            rest.insert(["role": "user", "content": system], at: 0)
        }
        return rest
    }

    /// The last `window` tokens are one stretch said `times` times over, back to back, for some
    /// stretch of 8 to 256 tokens: a loop.
    static func isLooping(_ tokens: [Int], window: Int = 1_536, times: Int = 4) -> Bool {
        guard tokens.count >= 64 else { return false }
        let tail = Array(tokens.suffix(window))
        for period in stride(from: 8, through: min(256, tail.count / times), by: 1) {
            let span = period * times
            guard span <= tail.count else { break }
            let base = tail.count - span
            var repeats = true
            for i in 0..<(span - period) where tail[base + i] != tail[base + i + period] { repeats = false; break }
            if repeats { return true }
        }
        return false
    }

    static func commonPrefix(_ a: [Int], _ b: [Int]) -> Int {
        var i = 0
        let limit = min(a.count, b.count)
        while i < limit, a[i] == b[i] { i += 1 }
        return i
    }

    /// The answer without the end-of-turn text a template may leave.
    static func cleaned(_ text: String) -> String {
        var out = text
        for marker in ["<|im_end|>", "<|endoftext|>", "<end_of_turn>", "<turn|>", "</s>"] { out = out.replacingOccurrences(of: marker, with: "") }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The non-Sendable model handle, read off the container's lock as ChatSession does: the weights
/// are read-only and the cache is ours.
final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// A cache's sliding-window layers (`RotatingKVCache`) copied at one token count. A window layer that
/// has wrapped cannot be trimmed back, so a rewind past it puts this copy back instead. The arrays are
/// real copies (a new buffer each, evaluated now): a reference to the live buffer would make every
/// later decode step copy it, because MLX writes in place only into a buffer nothing else holds.
struct WindowCopy: @unchecked Sendable {
    let tokenCount: Int
    /// Layer index → its keys and values, and its offset, write index and window.
    let layers: [Int: (state: [MLXArray], meta: [String])]

    static func hasWindows(_ layers: [KVCache]) -> Bool { layers.contains { $0 is RotatingKVCache } }

    /// Nil when the cache has no window layers (or one is still empty).
    static func take(_ layers: [KVCache], at tokenCount: Int) -> WindowCopy? {
        var copied: [Int: (state: [MLXArray], meta: [String])] = [:]
        for (index, layer) in layers.enumerated() {
            guard let window = layer as? RotatingKVCache else { continue }
            let state = window.state
            guard state.count == 2 else { return nil }
            copied[index] = (state.map { $0 * MLXArray(1).asType($0.dtype) }, window.metaState)
        }
        guard !copied.isEmpty else { return nil }
        eval(copied.values.flatMap(\.state))
        return WindowCopy(tokenCount: tokenCount, layers: copied)
    }

    /// Puts the window layers back as they were at `tokenCount`. The cache gets new array objects over
    /// the copy's buffers (`[.ellipsis]`, as `RotatingKVCache.copy` does): a one-token step writes into
    /// the object it holds, so handing it the copy's own would change the copy. Its first write copies
    /// the buffer once, and the copy stays good for the next rewind.
    func restore(into layers: [KVCache]) {
        for (index, saved) in self.layers {
            guard index < layers.count, let window = layers[index] as? RotatingKVCache else { continue }
            window.state = saved.state.map { $0[.ellipsis] }
            window.metaState = saved.meta
        }
    }
}
