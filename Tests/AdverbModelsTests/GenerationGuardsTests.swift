import Foundation
import Testing
@testable import AdverbCore
@testable import AdverbModels

@Suite struct GenerationGuardsTests {
    @Test func aLoopIsSeenAndProseIsNot() {
        let stretch = Array(100..<140)
        let looping = Array(0..<300) + Array(repeating: stretch, count: 5).flatMap { $0 }
        #expect(MLXLanguageModel.isLooping(looping))
        var varied: [Int] = []
        var x = 7
        for _ in 0..<2_000 { x = (x &* 1_103_515_245 &+ 12_345) & 0x7fff; varied.append(x % 5_000) }
        #expect(!MLXLanguageModel.isLooping(varied))
        #expect(!MLXLanguageModel.isLooping(Array(repeating: stretch, count: 3).flatMap { $0 }), "three times is a pattern, not yet a loop")
        #expect(!MLXLanguageModel.isLooping([1, 2, 3]))
    }

    @Test func thinkingIsSplitFromTheAnswerAsItArrives() {
        var opened = ThinkingSplitter(startsThinking: false)
        var pieces = opened.feed("  <thi") + opened.feed("nk>Plan the scenes.</th") + opened.feed("ink>\n<!doctype html>") + opened.finish()
        #expect(pieces.contains(.thinking("Plan the scenes.")))
        #expect(pieces.compactMap { if case .text(let t) = $0 { return t }; return nil }.joined() == "<!doctype html>")
        var inside = ThinkingSplitter(startsThinking: true)
        pieces = inside.feed("First, the headline.") + inside.feed("</think>\n\n{\"ok\": true}") + inside.finish()
        #expect(pieces.first == .thinking("First, the headline."))
        #expect(pieces.compactMap { if case .text(let t) = $0 { return t }; return nil }.joined() == "{\"ok\": true}")
        var plain = ThinkingSplitter(startsThinking: false)
        #expect((plain.feed("{\"a\": 1}") + plain.finish()) == [.text("{\"a\": 1}")])
        #expect(ThinkingSplitter.partialSuffix("abc</th", of: "</think>") == 4)
        // Gemma 4's block.
        var gemma = ThinkingSplitter(startsThinking: false)
        pieces = gemma.feed("<|channel>thought\nThe headline first.<chan") + gemma.feed("nel|>Read every page.") + gemma.finish()
        #expect(pieces.first == .thinking("\nThe headline first."))
        #expect(pieces.compactMap { if case .text(let t) = $0 { return t }; return nil }.joined() == "Read every page.")
        #expect(gemma.tags == ThinkingSplitter.gemma)
        #expect(ThinkingSplitter.openAtEnd(of: "<|turn>model\n<|channel>thought\n") == ThinkingSplitter.gemma)
        #expect(ThinkingSplitter.openAtEnd(of: "<|turn>model\n<|channel>thought\n<channel|>") == nil, "thinking off: the block is closed")
        #expect(ThinkingSplitter.openAtEnd(of: "<|im_start|>assistant\n<think>\n") == ThinkingSplitter.qwen)
    }

    @Test func aModelFolderSaysWhatItIs() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("adverb-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try #"{"model_type": "gemma4", "vision_config": {}, "text_config": {"max_position_embeddings": 262144}}"#
            .write(to: folder.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "{% if enable_thinking %}<|think|>{% endif %}".write(to: folder.appendingPathComponent("chat_template.jinja"), atomically: true, encoding: .utf8)
        try #"{"temperature": 1.0, "top_p": 0.95, "top_k": 64}"#.write(to: folder.appendingPathComponent("generation_config.json"), atomically: true, encoding: .utf8)
        let files = try #require(ModelFiles.load(folder))
        let info = files.info(id: ModelCatalog.gemma4.id)
        #expect(info.acceptsImages && info.thinks && info.contextTokens == 262_144 && info.title == "Gemma 4 31B")
        #expect(files.topK == 64 && files.takesThinkingSwitch)
        #expect(ModelInstaller.resolve(folder.path)?.path == folder.path)
    }
}
