import Foundation
import Testing
@testable import AdverbCore

@Suite struct AnswerParserTests {
    @Test func aJSONObjectIsFoundWhereverTheModelPutIt() throws {
        #expect(AnswerParser.object(in: #"{"lines":[{"at":0,"until":2,"text":"Hi."}]}"#)?["lines"]?.arrayValue?.count == 1)
        #expect(AnswerParser.object(in: "Here it is:\n```json\n{\"ok\": true, \"issues\": []}\n```\nDone.")?["ok"]?.boolValue == true)
        #expect(AnswerParser.object(in: "Sure. {\"a\": 1,} hope that helps")?["a"]?.intValue == 1, "a trailing comma")
        #expect(AnswerParser.object(in: "{\"text\": \"two\nlines\"}")?["text"]?.stringValue == "two\nlines", "a raw newline in a string")
        #expect(AnswerParser.object(in: #"{"path": "C:\d"}"#)?["path"]?.stringValue == #"C:\d"#, "a backslash that escapes nothing")
        #expect(AnswerParser.object(in: "no json here") == nil)
    }

    @Test func anAnswerCutOffIsClosedToItsLastWholeItem() throws {
        let cut = #"{"lines": [{"at": 0, "until": 2, "text": "One."}, {"at": 2, "until": 4, "text": "Tw"#
        let value = try #require(AnswerParser.object(in: cut))
        #expect(value["lines"]?.arrayValue?.count == 1)
    }

    @Test func aPageThenItsTrailerAssembleThePageResponse() throws {
        let answer = """
        <!doctype html><html><head><title>T</title></head><body class="P"><div id="stage"></div></body></html>
        === ADVERB JSON ===
        {"notes": {"summary": "A day.", "illustrative": ["Mara Ellis"], "softened": [], "sources": ["README"]},
         "a11y": {"alt_text": "A highlight.", "descriptions": [{"at": 0, "until": 6, "text": "A line is highlighted."}]}}
        """
        let page = try AnswerParser.decode(PageResponse.self, from: answer, format: Schemas.pageFormat)
        #expect(page.html.hasPrefix("<!doctype html>") && page.html.hasSuffix("</html>"))
        #expect(page.notes.illustrative == ["Mara Ellis"])
        #expect(page.a11y.descriptions.first?.until == 6)
    }

    @Test func aTrailerWithoutTheLineIsStillRead() throws {
        let answer = "```html\n<!DOCTYPE html><html><body></body></html>\n```\n{\"notes\": {\"summary\": \"s\"}, \"a11y\": {\"alt_text\": \"a\"}}"
        let page = try AnswerParser.decode(PageResponse.self, from: answer, format: Schemas.pageFormat)
        #expect(page.html.lowercased().hasPrefix("<!doctype html>"))
        #expect(page.notes.summary == "s" && page.notes.illustrative.isEmpty, "a key left out reads as empty")
        #expect(page.a11y.alt_text == "a")
    }

    @Test func aMissingOrCutPageSaysWhy() {
        #expect(throws: ModelError.unreadable("there was no page in it (from <!doctype html> to </html>).")) {
            try AnswerParser.decode(PageResponse.self, from: "I'll write the page now.\n=== ADVERB JSON ===\n{}", format: Schemas.pageFormat)
        }
        #expect(throws: ModelError.unreadable("the page stops before </html>: it ran out of room. Write it shorter.")) {
            try AnswerParser.decode(PageResponse.self, from: "<!doctype html><html><body><div>", format: Schemas.pageFormat)
        }
    }

    @Test func aReviewIsTheObjectAlone() throws {
        let review = try AnswerParser.decode(ReviewResponse.self, from: #"{"ok": false, "issues": ["Portrait at 12.6 s: the card runs off the edge."]}"#,
                                             format: Schemas.reviewFormat)
        #expect(!review.ok && review.issues.count == 1 && review.html.isEmpty)
        let fine = try AnswerParser.decode(ReviewResponse.self, from: #"{"issues": []}"#, format: Schemas.reviewFormat)
        #expect(fine.ok, "no issues and no verdict reads as ok")
    }

    @Test func numbersAndListsAreForgiven() throws {
        let narration = try AnswerParser.decode(NarrationResponse.self, from: #"{"lines": [{"at": "1.5", "until": 4, "text": "Hello."}]}"#,
                                                format: Schemas.narrationFormat)
        #expect(narration.lines.first?.at == 1.5)
        let plan = try AnswerParser.decode(PlanResponse.self, from: #"{"summary": "m", "arc": "One phase", "days": []}"#, format: Schemas.planFormat)
        #expect(plan.arc == ["One phase"] && plan.cautions.isEmpty)
        #expect(throws: ModelError.self) { try AnswerParser.decode(PlanResponse.self, from: #"{"summary": "m"}"#, format: Schemas.planFormat) }
    }

    @Test func theSkeletonKeepsTheSchemasOrder() throws {
        let skeleton = AnswerFormat.skeleton(Schemas.plan)
        let summary = try #require(skeleton.range(of: "\"summary\""))
        let days = try #require(skeleton.range(of: "\"days\""))
        #expect(summary.lowerBound < days.lowerBound, "the summary is asked for before thirty days")
        #expect(skeleton.contains("\"duration\": 15 | 30"))
        #expect(skeleton.contains("\"date\": \"YYYY-MM-DD\""))
        #expect(Schemas.pageFormat.instructions?.contains(AnswerParser.sentinel) == true)
        #expect(Schemas.planFormat.instructions?.contains("no code fence") == true)
        #expect(AnswerFormat.text.instructions == nil)
    }
}

@Suite struct OnDeviceSeamTests {
    @Test func theSkillIsTrimmedForTheWriter() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AdverbCore/Resources/Prompts/SKILL.md")
        let skill = try String(contentsOf: source, encoding: .utf8)
        let trimmed = SkillText.forModel(skill)
        #expect(skill.contains("### render.py") && !trimmed.contains("### render.py"))
        #expect(!trimmed.contains("## 8. Contact sheets") && !trimmed.contains("## 9. Final message"))
        #expect(trimmed.contains("## 6. Dual-orientation page template") && trimmed.contains("## 7. Scene recipes"))
        #expect(trimmed.count < skill.count - 2_000)
        #expect(SkillText.forModel("# A skill without those sections\n") == "# A skill without those sections\n")
    }

    @Test func theCatalogIsPinnedUnderRaoStudios() {
        for spec in ModelCatalog.all {
            #expect(spec.id.hasPrefix("rao-studios/"), "\(spec.id)")
            if let revision = spec.revision { #expect(revision.count == 40 && revision.allSatisfy(\.isHexDigit), "\(spec.id)") }
        }
        #expect(Set(ModelCatalog.all.map(\.id)).count == ModelCatalog.all.count)
        #expect(ModelCatalog.speech.allSatisfy { $0.packID != nil && $0.isInstallable })
        #expect(ModelCatalog.text.allSatisfy(\.isInstallable) && ModelCatalog.vision.allSatisfy(\.isInstallable))
        #expect(ModelCatalog.text == [ModelCatalog.gemma4, ModelCatalog.nemotronSuper, ModelCatalog.ministral3])
        #expect(ModelCatalog.all.allSatisfy { !$0.family.hasPrefix("qwen") }, "no Qwen model is offered")
    }

    @Test func aMacIsOfferedWhatFitsIt() {
        #expect(ModelCatalog.recommended(memoryGB: 128).text == ModelCatalog.gemma4)
        #expect(ModelCatalog.recommended(memoryGB: 32).text == ModelCatalog.gemma4)
        #expect(ModelCatalog.recommended(memoryGB: 128).vision == nil, "Gemma 4 reads images itself")
        let small = ModelCatalog.recommended(memoryGB: 24)
        #expect(small.text == ModelCatalog.ministral3 && small.vision == nil)
        #expect(ModelCatalog.recommended(memoryGB: 128).speech.map(\.packID) == [ModelCatalog.paradeePackID, ModelCatalog.kokoroPackID])
        #expect(ModelCatalog.vision(for: ModelCatalog.gemma4) == nil)
        #expect(ModelCatalog.vision(for: ModelCatalog.nemotronSuper, memoryGB: 128) == ModelCatalog.ministral3)
        for memory in [16, 24, 32, 64, 128] {
            let set = ModelCatalog.recommended(memoryGB: memory).all
            let families = set.map(\.family).filter { $0.hasPrefix("qwen") }
            #expect(families.isEmpty, "no Qwen model in a default set")
            let unpublished = set.filter { !$0.isInstallable }
            #expect(unpublished.isEmpty)
        }
        #expect(ModelCatalog.all.filter { $0.id == ModelCatalog.ministral3.id }.count == 1)
    }

    @Test func theDigestIsTheStablePartOfEveryRequest() throws {
        let prompts = PromptLibrary(skill: "SKILL", addendum: "ADDENDUM")
        #expect(prompts.system.hasPrefix("SKILL") && prompts.system.hasSuffix("ADDENDUM"))
        var campaign = Campaign(projectID: UUID(), name: "N", brief: sampleBrief(days: 3))
        campaign.days = PlanValidator.days(samplePlan(dates: campaign.brief.postDates), brief: campaign.brief)
        let project = Project(slug: "ambient", name: "Ambient", contextPath: "/tmp", app: .ambient)
        let turns = prompts.build(digest: "DIGEST", day: campaign.days[0], campaign: campaign, project: project)
        #expect(turns.count == 1 && turns[0].parts.first == .text("DIGEST", stable: true))
        let redo = prompts.redo(previous: turns, html: "<html></html>", note: "calmer headline")
        #expect(redo.count == 3 && redo[1].role == .assistant && redo[2].text.contains("calmer headline"))
        let review = prompts.review(day: campaign.days[0], html: "<html></html>", sheet: Data([1, 2, 3]))
        #expect(review[0].parts.filter(\.isImage).count == 1)
        let noted = prompts.build(digest: "DIGEST", day: campaign.days[0], campaign: campaign, project: project, note: "show the panel sooner")
        #expect(noted[0].text.contains("show the panel sooner"))
    }

    @Test func wordsAreSpreadOverTheVoice() {
        let words = WordTimings.spread("Notes in the margin, of everything.", start: 0.1, end: 2.1)
        #expect(words.map(\.text) == ["Notes", "in", "the", "margin,", "of", "everything."])
        #expect(words.first?.start == 0.1 && words.last?.end == 2.1)
        #expect(zip(words, words.dropFirst()).allSatisfy { $0.end <= $1.start })
        let margin = words[3], of = words[4]
        #expect(of.start - margin.end > words[1].start - words[0].end, "a comma leaves a longer pause than a space")
        #expect(WordTimings.spread("", start: 0, end: 1).isEmpty)
        #expect(WordTimings.spread("One two", start: 0, end: 2, weights: [3, 1]).first.map { $0.end - $0.start }! > 1)
    }

    @Test func tokenUsageReadsAsTime() throws {
        let u = TokenUsage(input: 1_055, output: 8_000, cacheRead: 29_461, seconds: 400)
        #expect(u.line == "30,516 read (29,461 from cache), 8,000 written in 6 min 40 s")
        #expect(u.tokensPerSecond == 20)
        #expect(TokenUsage.duration(3_725) == "1 h 2 min")
        #expect(try JSONDecoder().decode(TokenUsage.self, from: Data(#"{"input":1,"output":2,"cacheRead":3,"cacheWrite":4}"#.utf8)).seconds == 0)
    }
}
