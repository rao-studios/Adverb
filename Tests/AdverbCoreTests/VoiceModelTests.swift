import Foundation
import Testing
@testable import AdverbCore

@Suite struct VoiceModelTests {
    @Test func languagesRoundTrip() throws {
        #expect(Language.allCases.count == 29)
        #expect(Language.targets.count == 28 && !Language.targets.contains(.english))
        #expect(Set(Language.allCases.map(\.code)).count == 29)
        #expect(Language.indonesian.code == "id" && Language.filipino.code == "fil")
        #expect(try JSONDecoder().decode([Language].self, from: Data(#"["de","es"]"#.utf8)) == [.german, .spanish])
        // Unknown codes drop; duplicates fold; canonical order.
        #expect(Language.decode(["es", "xx", "de", "es"]) == [.german, .spanish])
        #expect(Language.allCases.allSatisfy { !$0.title.isEmpty && !$0.nativeTitle.isEmpty })
    }

    @Test func assetDecodesWithoutTheVoiceFields() throws {
        // Whole seconds: the files store ISO-8601 dates without fractions.
        let when = Date(timeIntervalSince1970: 1_790_000_000)
        let plain = Asset(folder: "assets/01-a", duration: 15, pagePath: "assets/01-a/page.html", builtAt: when)
        var json = try JSONCoding.lineEncoder().encode(plain)
        var object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        object.removeValue(forKey: "voiceOver"); object.removeValue(forKey: "warp")
        json = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONCoding.decoder().decode(Asset.self, from: json)
        #expect(decoded.voiceOver == nil && decoded.warp == nil)

        var narrated = plain
        let english = VoiceTrack(language: .english, scriptPath: "assets/01-a/voice/en/script.json",
                                 lines: [NarrationLine(index: 0, text: "Hello.", at: 0.2, until: 2, spokenStart: 0.05, spokenEnd: 0.7)], generatedAt: when)
        var vo = VoiceOver(selection: VoiceSelection(voiceID: "v", voiceName: "Rachel"), english: english, appliedAt: when)
        vo.upsert(VoiceTrack(language: .spanish, scriptPath: "s", lines: [], generatedAt: when))
        vo.upsert(VoiceTrack(language: .german, scriptPath: "g", lines: [], generatedAt: when))
        #expect(vo.languages.map(\.language) == [.german, .spanish])
        narrated.voiceOver = vo
        narrated.warp = TimeWarp(knots: [.init(page: 0, real: 0), .init(page: 15, real: 15)])
        let back = try JSONCoding.decoder().decode(Asset.self, from: JSONCoding.lineEncoder().encode(narrated))
        #expect(back == narrated)
        #expect(back.voiceOver?.track(.english)?.lines.first?.isRecorded == false)
        #expect(back.voiceOver?.freshLanguages == [])
    }

    @Test func briefDecodesWithoutAVoice() throws {
        let brief = sampleBrief()
        var object = try #require(try JSONSerialization.jsonObject(with: JSONCoding.lineEncoder().encode(brief)) as? [String: Any])
        object.removeValue(forKey: "voiceOver")
        let decoded = try JSONCoding.decoder().decode(CampaignBrief.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.voiceOver == nil)
        var voiced = brief
        voiced.voiceOver = VoiceSelection(voiceID: "v", voiceName: "Rachel", modelID: "eleven_v3")
        #expect(try JSONCoding.decoder().decode(CampaignBrief.self, from: JSONCoding.lineEncoder().encode(voiced)) == voiced)
    }

    @Test func silentBuiltDaysAreTheOnesToCatchUp() {
        var campaign = Campaign(projectID: UUID(), name: "N", brief: sampleBrief(days: 3))
        campaign.days = PlanValidator.days(samplePlan(dates: campaign.brief.postDates), brief: campaign.brief)
        let render = Render(orientation: .portrait, path: "p.mp4", seconds: 15)
        campaign.days[0].asset = Asset(folder: "a", duration: 15, pagePath: "a/page.html", renders: [render])
        campaign.days[1].asset = Asset(folder: "b", duration: 15, pagePath: "b/page.html", renders: [render],
                                       voiceOver: VoiceOver(selection: VoiceSelection(voiceID: "v", voiceName: "R"),
                                                            english: VoiceTrack(language: .english, scriptPath: "s", lines: [])))
        #expect(campaign.silentBuiltDays == [campaign.days[0].index])
        #expect(!campaign.isNarrated)
        campaign.brief.voiceOver = VoiceSelection(voiceID: "v", voiceName: "R")
        #expect(campaign.isNarrated)
    }

    @Test func pathsNameLanguages() {
        let a = CampaignPaths(root: URL(fileURLWithPath: "/w/c")).asset("03-highlight")
        #expect(a.video(.portrait, .german).lastPathComponent == "03-highlight-portrait.de.mp4")
        #expect(a.video(.portrait, .english) == a.video(.portrait))
        #expect(a.vtt(.landscape, .spanish).lastPathComponent == "03-highlight-landscape.es.vtt")
        #expect(a.srt(.landscape, .english) == a.srt(.landscape))
        #expect(a.transcript(.french).lastPathComponent == "03-highlight.fr.transcript.md")
        #expect(a.clip(.english, 3).path.hasSuffix("03-highlight/voice/en/line-03.mp3"))
        #expect(a.script(.japanese).path.hasSuffix("voice/ja/script.json"))
        #expect(a.screenVTT(.portrait).lastPathComponent == "03-highlight-portrait.screen.vtt")
    }

    @Test func runKindsNameThemselves() {
        #expect(RunKind.voice(day: 3).slug == "voice")
        #expect(RunKind.languages(day: 3, [.german]).title == "German")
        #expect(RunKind.languages(day: 3, [.german, .french]).title == "2 languages")
        let paths = CampaignPaths(root: Fixture.temp())
        let log = RunLog(paths: paths, campaignID: UUID(), kind: .languages(day: 4, [.german]), model: "m")
        #expect(log.url.lastPathComponent.hasSuffix("-languages-day4.log"))
        log.add(voice: VoiceUsage(characters: 120, requests: 2))
        log.add(voice: VoiceUsage(characters: 80, requests: 1))
        #expect(log.voice?.characters == 200 && log.voice?.requests == 3)
        log.finish(.succeeded)
        let run = try? JSONCoding.read(GenerationRun.self, from: log.jsonURL)
        #expect(run?.voice?.characters == 200)
        #expect((try? String(contentsOf: log.url, encoding: .utf8))?.contains("voice: 200 characters in 3 requests") == true)
    }
}
