import Foundation
import Testing
@testable import AdverbAgents
@testable import AdverbCore

/// A model that answers from a script, one answer per call, and keeps what it was asked.
final class ScriptedModel: LanguageModel, @unchecked Sendable {
    let info = ModelInfo(id: "test/scripted", contextTokens: 32_768)
    private let lock = NSLock()
    private var answers: [String]
    private(set) var requests: [ModelRequest] = []

    init(_ answers: [String]) { self.answers = answers }

    func complete(_ request: ModelRequest, onEvent: @escaping @Sendable (ModelEvent) -> Void) async throws -> ModelAnswer {
        let text = lock.withLock { () -> String in requests.append(request); return answers.isEmpty ? "" : answers.removeFirst() }
        onEvent(.text(text))
        return ModelAnswer(text: text, usage: TokenUsage(input: 10, output: 5, seconds: 1), model: info.id)
    }
}

@Suite struct ModelCallTests {
    func log() -> RunLog {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("adverb-modelcall-\(UUID().uuidString)")
        return RunLog(paths: CampaignPaths(root: root), campaignID: UUID(), kind: .plan, model: "test/scripted")
    }

    @Test func theFormatIsSaidAfterTheRequest() {
        let request = ModelRequest(system: "s", turns: [.user([.text("DIGEST", stable: true), .text("Write the lines.")])], format: Schemas.narrationFormat)
        let said = ModelCall.withInstructions(request)
        #expect(said.turns[0].parts.count == 3)
        #expect(said.turns[0].parts[0] == .text("DIGEST", stable: true), "the stable part stays first")
        #expect(said.turns[0].text.contains("\"lines\""))
        #expect(said.answerPrefix == "{", "a model that does not think is started in the format")
        var thinking = request; thinking.thinking = .on(budget: 100)
        #expect(ModelCall.withInstructions(thinking).answerPrefix == nil, "a thinking model plans first")
        let page = ModelRequest(system: "s", turns: [.user("Write it.")], format: Schemas.pageFormat)
        #expect(ModelCall.withInstructions(page).answerPrefix == "<!doctype html>")
        #expect(ModelCall.withInstructions(ModelRequest(system: "s", turns: [.user("Look.")], format: Schemas.reviewFormat)).answerPrefix == "{")
    }

    @Test func anUnreadableAnswerIsSentBackOnceWithWhy() async throws {
        let model = ScriptedModel(["I will now write the lines.", #"{"lines": [{"at": 0.2, "until": 3, "text": "Notes in the margin."}]}"#])
        let box = EventBox()
        let request = ModelRequest(system: "s", turns: [.user("Write the lines.")], format: Schemas.narrationFormat, label: "voice-over")
        let (answer, _) = try await ModelCall.structured(NarrationResponse.self, model: model, request: request, log: log(), emit: { box.add($0) })
        #expect(answer.lines.first?.text == "Notes in the margin.")
        #expect(model.requests.count == 2)
        let second = model.requests[1].turns
        #expect(second.count == 3 && second[1].role == .assistant && second[1].text == "I will now write the lines.")
        #expect(second[0] == model.requests[0].turns[0], "the first turn is sent as it was, so the cache holds it")
        #expect(second[2].text.contains("there was no JSON object in it."))
        #expect(box.events.contains(.step("Asking again")))
        #expect(box.events.contains { if case .writing = $0 { return true }; return false })
    }

    @Test func aSecondUnreadableAnswerFailsTheCall() async {
        let model = ScriptedModel(["nope", "still nope"])
        let request = ModelRequest(system: "s", turns: [.user("Write the lines.")], format: Schemas.narrationFormat)
        await #expect(throws: ModelError.self) {
            _ = try await ModelCall.structured(NarrationResponse.self, model: model, request: request, log: log(), emit: { _ in })
        }
        #expect(model.requests.count == 2)
    }
}
