import Foundation
import Testing
@testable import AdverbCore

@Suite struct ClaudeTests {
    func run(_ fixture: String) throws -> (MessageAccumulator, [ClaudeEvent]) {
        var acc = MessageAccumulator()
        var events: [ClaudeEvent] = []
        for line in Fixture.text("sse/\(fixture)").components(separatedBy: "\n") { events += try acc.consume(line) }
        return (acc, events)
    }

    @Test func readsAStructuredAnswer() throws {
        let (acc, events) = try run("plan.txt")
        #expect(acc.finished)
        #expect(acc.message.text == #"{"ok":true}"#)
        #expect(acc.message.stopReason == "end_turn")
        #expect(acc.message.usage == TokenUsage(input: 120, output: 420, cacheRead: 9000, cacheWrite: 0))
        #expect(events.contains(.activity("Planning the arc.")))
        // The thinking block keeps its signature for a replay.
        #expect(acc.message.content.first?["signature"]?.stringValue == "sig123")
        struct OK: Decodable { var ok: Bool }
        #expect(try ClaudeClient.decode(OK.self, from: acc.message).ok)
    }

    @Test func readsARefusal() throws {
        let (acc, _) = try run("refusal.txt")
        #expect(acc.message.stopReason == "refusal")
        #expect(acc.message.stopDetails?["category"]?.stringValue == "cyber")
    }

    @Test func readsAServerToolPause() throws {
        let (acc, events) = try run("pause.txt")
        #expect(acc.message.stopReason == "pause_turn")
        #expect(acc.message.content.count == 2)
        #expect(acc.message.content[0]["input"]?["url"]?.stringValue == "https://ambient.rao.nyc")
        #expect(events.contains(.activity("Reading ambient.rao.nyc")))
    }

    @Test func anErrorFrameThrows() {
        #expect(throws: ClaudeError.stream("Overloaded")) { _ = try run("error.txt") }
    }

    @Test func requestBodyHasTheCurrentShape() throws {
        let client = ClaudeClient(config: ClaudeConfig(apiKey: Secret("sk-test")!, model: "claude-opus-5-5", effort: "high"))
        let request = ClaudeRequest(system: [SystemBlock("skill"), SystemBlock("addendum", cache: true)],
                                    messages: [.user([.text("digest", cache: true), .text("plan it")])],
                                    schema: Schemas.review, tools: [ClaudeRequest.webFetch(domains: ["ambient.rao.nyc"])])
        let body = client.body(request)
        #expect(body["model"]?.stringValue == "claude-opus-5-5")
        #expect(body["stream"]?.boolValue == true)
        #expect(body["thinking"]?["type"]?.stringValue == "adaptive")
        #expect(body["output_config"]?["effort"]?.stringValue == "high")
        #expect(body["output_config"]?["format"]?["type"]?.stringValue == "json_schema")
        #expect(body["fallbacks"]?.stringValue == "default")
        #expect(body["system"]?[1]?["cache_control"]?["ttl"]?.stringValue == "1h")
        #expect(body["system"]?[0]?["cache_control"] == nil)
        #expect(body["tools"]?[0]?["type"]?.stringValue == "web_fetch_20260209")
        // No sampling parameters on this API version, no budget_tokens.
        for key in ["temperature", "top_p", "top_k"] { #expect(body[key] == nil) }
        #expect(body["thinking"]?["budget_tokens"] == nil)
        let r = try client.urlRequest(request)
        #expect(r.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(r.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        #expect(r.value(forHTTPHeaderField: "x-api-key") == "sk-test")
    }

    @Test func schemasCloseEveryObject() {
        func check(_ v: JSONValue) {
            if v["type"]?.stringValue == "object" {
                #expect(v["additionalProperties"]?.boolValue == false)
                let required = Set(v["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
                let keys = Set(v["properties"]?.objectValue?.keys.map { $0 } ?? [])
                #expect(required == keys)
            }
            v["properties"]?.objectValue?.values.forEach(check)
            if let items = v["items"] { check(items) }
        }
        [Schemas.plan, Schemas.page, Schemas.review, Schemas.retime, Schemas.narration].forEach(check)
    }

    @Test func haikuGetsNoFallbacks() {
        let client = ClaudeClient(config: ClaudeConfig(apiKey: Secret("k")!, model: "claude-haiku-5-5"))
        #expect(client.body(ClaudeRequest(system: [], messages: []))["fallbacks"] == nil)
    }

    @Test func usageCosts() {
        let u = TokenUsage(input: 1_000_000, output: 100_000, cacheRead: 1_000_000, cacheWrite: 0)
        #expect(abs(u.estimatedUSD(model: "claude-opus-5-5") - (4 + 2 + 0.4)) < 1e-9)
        #expect(abs(u.cacheHitRate - 0.5) < 1e-9)
    }
}
