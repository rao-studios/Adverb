//
//  main.swift
//  ModelProbe
//
//  WHAT: The generative steps headless, on this Mac, timed: one answer from a model, a campaign
//        planned, a day written to its contact sheet (and rendered), a line spoken. How models are
//        compared against the reference sheets, and how the stack is checked without the app.
//
//    adverb-model-probe ask    --model <repo|path> [--think] [--max N] "<prompt>"
//    adverb-model-probe bench  --model <repo|path>               (prefill and decode speed, warm)
//    adverb-model-probe cache  --model <repo|path>               (prefix reuse: two calls sharing a long prefix)
//    adverb-model-probe plan   --campaign <campaign folder> --model <repo|path> [--think]
//    adverb-model-probe draft  --campaign <campaign folder> --day N --model <repo|path> [--eyes <repo|path>|--no-eyes]
//                              [--think] [--note "<what to change>"] [--render] [--voice]
//    adverb-model-probe render --campaign <campaign folder> --day N
//    adverb-model-probe speak  [--pack <id>] [--voice af_heart] [--out line.wav] "<text>"
//    adverb-model-probe download --model <repo> [--revision <commit>] | --voice-pack paradee-af-heart|kokoro-82m-en
//
//  A campaign folder is <workdir>/Adverb/<project>/campaigns/<id>. The probe writes to it as the
//  app does: run it on a copy, never on a campaign you are posting from.
//

import AdverbAgents
import AdverbCore
import AdverbModels
import AdverbRender
import AdverbVoice
import AppKit
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let args = Array(CommandLine.arguments.dropFirst())

func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func has(_ flag: String) -> Bool { args.contains(flag) }
/// The last argument that is not a flag or a flag's value.
var freeText: String? {
    var skip = false
    var out: String?
    for a in args.dropFirst() {
        if skip { skip = false; continue }
        if a.hasPrefix("--") { skip = !["--think", "--render", "--voice", "--no-eyes", "--stream"].contains(a); continue }
        out = a
    }
    return out
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("model-probe: \(message)\n".utf8)); exit(1)
}

/// Run events as lines; the answer's tail as it is written when --stream.
let printer: @Sendable (GenerationEvent) -> Void = { event in
    switch event {
    case .step(let s): print("▸ \(s)")
    case .log(let s): print("  \(s)")
    case .problem(let s): print("⚠︎ \(s)")
    case .writing(let s): if has("--stream") { FileHandle.standardOutput.write(Data(s.utf8)) }
    case .activity(let s): if has("--stream") { FileHandle.standardError.write(Data(s.utf8)) }
    case .planned(let n): print("✓ planned \(n) days")
    case .sheet(let d): print("✓ day \(d): sheet drawn")
    case .dayDone(let d): print("✓ day \(d) written")
    case .usage, .progress, .voiceUsage: break
    }
}

struct CampaignLocation {
    let workspace: Workspace
    let projectSlug: String
    let campaignID: UUID
    var paths: CampaignPaths { CampaignPaths(workspace: workspace, projectSlug: projectSlug, campaignID: campaignID) }

    init(_ path: String) {
        let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        guard let id = UUID(uuidString: folder.lastPathComponent) else { fail("\(path) is not a campaign folder (…/campaigns/<id>)") }
        campaignID = id
        let project = folder.deletingLastPathComponent().deletingLastPathComponent()
        projectSlug = project.lastPathComponent
        workspace = Workspace(workdir: project.deletingLastPathComponent().deletingLastPathComponent())
    }
}

func compute(location: CampaignLocation?, model: String?) throws -> AdverbCompute {
    var settings = AdverbSettings.load()
    settings.thinking = has("--think")
    settings.sheetGate = !has("--render")
    if has("--no-eyes") { settings.reviewPass = false }
    let text = ModelPool.shared.handle(model ?? settings.textModelID)
    let eyesID = value("--eyes")
    let vision: (any LanguageModel)? = eyesID.map { ModelPool.shared.handle($0, slot: .vision) } ?? (text.info.acceptsImages ? text : nil)
    let workspace = location?.workspace ?? Workspace(workdir: URL(fileURLWithPath: NSTemporaryDirectory()))
    let voice: (any SpeechProvider)? = has("--voice") || location == nil ? VoiceLibrary.shared : nil
    return AdverbCompute(text: text, vision: vision, voice: voice, prompts: try PromptLibrary.load(skillPath: settings.skillPath),
                         workspace: workspace, settings: settings)
}

func timed(_ body: () async throws -> Void) async {
    let start = Date()
    do {
        try await body()
        print(String(format: "done in %@", TokenUsage.duration(Date().timeIntervalSince(start))))
        exit(0)
    } catch {
        fail("\(error) (after \(TokenUsage.duration(Date().timeIntervalSince(start))))")
    }
}

guard let command = args.first else {
    fail("usage: adverb-model-probe ask|cache|plan|draft|render|speak|download …")
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    await timed {
        switch command {
        case "download" where value("--voice-pack") != nil:
            guard let spec = ModelCatalog.speechSpec(pack: value("--voice-pack")!) else { fail("no voice pack \(value("--voice-pack")!)") }
            let folder = try await VoicePackInstaller.download(spec) { p in print(String(format: "  %.0f %%", p * 100)) }
            print("✓ \(folder.path)")

        case "download":
            guard let id = value("--model") else { fail("--model <repo>") }
            let folder = try await ModelInstaller.download(id, revision: value("--revision") ?? "main") { p in
                print(String(format: "  %.0f %%", p * 100))
            }
            print("✓ \(folder.path)")

        case "ask":
            let c = try compute(location: nil, model: value("--model"))
            guard let prompt = freeText else { fail("a prompt") }
            let request = ModelRequest(system: "You are a careful, concise assistant.", turns: [.user(prompt)],
                                       maxTokens: Int(value("--max") ?? "") ?? 1_024, thinking: has("--think") ? .on(budget: 2_048) : .off, label: "ask")
            let answer = try await c.text.complete(request) { event in
                switch event {
                case .status(let s): print("  \(s)")
                case .thinking(let t): if has("--stream") { FileHandle.standardError.write(Data(t.utf8)) }
                case .text(let t): if has("--stream") { FileHandle.standardOutput.write(Data(t.utf8)) }
                case .usage: break
                }
            }
            if !has("--stream") {
                if !answer.thinking.isEmpty { print("— thinking —\n\(answer.thinking.prefix(1_500))\n— answer —") }
                print(answer.text)
            }
            print("\n\(c.text.info.title): \(answer.usage.line) · \(String(format: "%.1f", answer.usage.tokensPerSecond)) tok/s\(answer.truncated ? " · truncated" : "")")

        case "cache":
            let c = try compute(location: nil, model: value("--model"))
            let skill = c.prompts.system
            let digest = String(repeating: "The project keeps its notes in the margin of every page. ", count: 400)
            for (i, ask) in ["Name one colour from the brand system.", "Name one font from the brand system."].enumerated() {
                let request = ModelRequest(system: skill, turns: [.user([.text(digest, stable: true), .text(ask)])], maxTokens: 64, label: "cache \(i + 1)")
                let answer = try await c.text.complete(request) { if case .status(let s) = $0 { print("  \(s)") } }
                print("call \(i + 1): \(answer.usage.line) → \(answer.text.prefix(120))")
            }

        case "bench":
            // Prefill and decode speed, warm: distinct prompts (no shared prefix) of growing size.
            let c = try compute(location: nil, model: value("--model"))
            let words = ["margin", "thread", "notes", "gold", "platinum", "seal", "page", "voice", "scene", "frame", "month", "post"]
            for (i, size) in [512, 512, 2_048, 8_192].enumerated() {
                var text = "Run \(i). "
                var n: UInt = UInt(i)
                while text.count < size * 5 { text += words[Int(n % UInt(words.count))] + " "; n = n &* 31 &+ 7 }
                let request = ModelRequest(system: "Answer briefly.", turns: [.user(text + "\nCount the words above, roughly, then write a 200-word story about a lighthouse.")],
                                           maxTokens: 256, label: "bench")
                let t0 = Date()
                let first = FirstToken()
                let answer = try await c.text.complete(request) { event in
                    if case .text = event { first.mark() } else if case .thinking = event { first.mark() }
                }
                let total = Date().timeIntervalSince(t0)
                let prefill = first.seconds(since: t0) ?? total
                let decode = max(0.001, total - prefill)
                print(String(format: "prompt %6d tok · written %4d tok · %.1f s total · prefill %.1f s (%.0f tok/s) · decode %.1f tok/s",
                             answer.usage.input, answer.usage.output, total, prefill, Double(answer.usage.input) / max(0.001, prefill),
                             Double(max(0, answer.usage.output - 1)) / decode))
            }

        case "plan":
            guard let campaign = value("--campaign") else { fail("--campaign <folder>") }
            let location = CampaignLocation(campaign)
            let c = try compute(location: location, model: value("--model"))
            try await PlanJob.run(projectSlug: location.projectSlug, campaignID: location.campaignID, compute: c, emit: printer)
            let planned = try await CampaignLedger.shared.read(location.paths)
            for day in planned.days {
                print("\(day.date)  \(day.topic.duration)s  \(day.topic.slug)  \(day.topic.headline)  · \(day.postTimeLocal) \(day.primary.title)")
            }

        case "draft", "render":
            guard let campaign = value("--campaign"), let day = Int(value("--day") ?? "") else { fail("--campaign <folder> --day N") }
            let location = CampaignLocation(campaign)
            let c = try compute(location: location, model: value("--model"))
            if command == "draft" {
                try await DraftJob.run(projectSlug: location.projectSlug, campaignID: location.campaignID, dayIndex: day, note: value("--note"),
                                       compute: c, emit: printer)
            }
            if command == "render" || has("--render") {
                try await RenderJob.run(projectSlug: location.projectSlug, campaignID: location.campaignID, dayIndex: day, compute: c, emit: printer)
            }
            let written = try await CampaignLedger.shared.read(location.paths)
            if let d = written.day(day), let asset = d.asset {
                print("status: \(d.status.rawValue)\(d.problem.map { " · \($0)" } ?? "")")
                if let sheet = asset.sheetPath { print("sheet: \(location.paths.url(sheet).path)") }
                print("page: \(location.paths.url(asset.pagePath).path)")
                for r in asset.renders { print("\(r.orientation.rawValue): \(location.paths.url(r.path).path)") }
            }

        case "speak":
            guard let text = freeText else { fail("the words to speak") }
            let library = VoiceLibrary.shared
            guard let pack = value("--pack").flatMap({ library.pack($0) }) ?? library.packs.first else { fail("no voice pack is on this Mac") }
            let voice = try await library.synthesizer(pack: pack.id)
            let clip = try await voice.speak(SpeechRequest(text: text, voiceID: value("--voice") ?? pack.voices.first?.id ?? "af_heart"))
            let out = URL(fileURLWithPath: value("--out") ?? "line.wav")
            try WAVFile.write(clip.samples, sampleRate: clip.sampleRate, to: out)
            print(String(format: "%@ · %.2f s (voice %.2f–%.2f s) · %@ timing", out.path, clip.seconds, clip.spokenStart, clip.spokenEnd,
                         clip.exactTiming ? "exact" : "estimated"))
            for w in clip.words { print(String(format: "  %5.2f–%5.2f  %@", w.start, w.end, w.text)) }

        default:
            fail("unknown command \(command)")
        }
    }
}
app.run()


/// When the first piece of an answer arrived: the end of the prompt's prefill, near enough.
final class FirstToken: @unchecked Sendable {
    private let lock = NSLock()
    private var at: Date?
    func mark() { lock.lock(); if at == nil { at = Date() }; lock.unlock() }
    func seconds(since start: Date) -> Double? { lock.lock(); defer { lock.unlock() }; return at.map { $0.timeIntervalSince(start) } }
}
