//
//  main.swift
//  RenderProbe
//
//  WHAT: One kit page through the native renderer, timed: frames as PNGs, an MP4, its report, and
//        the caption samples. The check the renderer was built against, kept as a diagnostic.
//
//    swift run adverb-render-probe <page.html> <P|L> <out-dir> [--frames N] [--supersample] [--bitrate Mbps]
//
//  The page's folder must hold the kit (kit.css, kit.js, fonts/, assets/), as a project's does.
//

import AdverbCore
import AdverbRender
import AppKit
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments

// Subcommands on finished files: `sheet <portrait.mp4> <landscape.mp4> <title> <out.jpg>`,
// `grab <video.mp4> <seconds> <out.png>`, `inspect <video.mp4>`, `beats <song>`.
if args.count >= 2, ["sheet", "grab", "inspect", "beats"].contains(args[1]) {
    let done = DispatchSemaphore(value: 0)
    Task {
        do {
            switch args[1] {
            case "sheet":
                try await ContactSheet.make(portrait: URL(fileURLWithPath: args[2]), landscape: URL(fileURLWithPath: args[3]),
                                            title: args[4], duration: Int(try await FrameGrabber(url: URL(fileURLWithPath: args[2])).duration().rounded()),
                                            to: URL(fileURLWithPath: args[5]))
            case "grab":
                let image = try await FrameGrabber(url: URL(fileURLWithPath: args[2])).image(at: Double(args[3]) ?? 0)
                try ImageFiles.writePNG(image, to: URL(fileURLWithPath: args[4]))
            case "beats":
                let t0 = Date()
                let (samples, duration) = try await AudioDecoder.mono(URL(fileURLWithPath: args[2]))
                let grid = BeatAnalysis.analyze(samples: samples)
                print(String(format: "%.1f s song · %.1f BPM · confidence %.2f · %d beats · %d downbeats%@ · %.2f s", duration, grid.bpm, grid.confidence,
                             grid.beats.count, grid.downbeats.count, grid.nominal ? " · nominal" : "", Date().timeIntervalSince(t0)))
                print("first beats: \(grid.beats.prefix(8)) · first downbeats: \(grid.downbeats.prefix(4)) · in-point for 15 s: \(grid.suggestedInPoint(for: 15))")
            default:
                print(try await RenderInspector.inspect(URL(fileURLWithPath: args[2])).line)
            }
        } catch { FileHandle.standardError.write(Data("\(error)\n".utf8)) }
        done.signal()
    }
    done.wait()
    exit(0)
}
guard args.count >= 4 else {
    FileHandle.standardError.write(Data("usage: adverb-render-probe <page.html> <P|L> <out-dir> [--frames N] [--supersample] [--bitrate Mbps]\n".utf8))
    exit(2)
}
// `chrome <page.html> <P|L> <out.mp4>`: the Chrome renderer (the page's folder holds the kit).
if args.count >= 5, args[1] == "chrome" {
    let done = DispatchSemaphore(value: 0)
    Task {
        do {
            let page = URL(fileURLWithPath: args[2]).standardizedFileURL
            let o: Orientation = args[3].uppercased() == "L" ? .landscape : .portrait
            let t0 = Date()
            let out = try await ChromeRenderer.render(page: page, kit: page.deletingLastPathComponent(), orientation: o, to: URL(fileURLWithPath: args[4]),
                                                      options: RenderOptions(), duration: 15, progress: { _ in }, isCancelled: { false })
            print(String(format: "chrome: %.1f s · %@ · %d caption samples", Date().timeIntervalSince(t0), out.report.line, out.captions.count))
            if !out.report.warnings.isEmpty { print("warnings: \(out.report.warnings)") }
        } catch { FileHandle.standardError.write(Data("chrome failed: \(error)\n".utf8)) }
        done.signal()
    }
    done.wait()
    exit(0)
}

// `fixture <workdir> <context> <sample-page.html>`: a workspace for looking at the app without a key:
// a project, a planned campaign, two days built from the sample page.
if args.count >= 5, args[1] == "fixture" {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    Task { @MainActor in
        do {
            let workspace = Workspace(workdir: URL(fileURLWithPath: args[2], isDirectory: true))
            try workspace.prepare()
            let project = try ProjectStore(workspace: workspace).create(name: "Ambient", contextPath: args[3], app: .ambient, label: .gold, tags: ["reader", "mac"])
            let store = CampaignStore(workspace: workspace, project: project)
            let brief = CampaignBrief(startDate: "2026-11-02", lengthDays: 30, timeZone: "America/New_York", audienceRegion: "Mac readers and researchers in the US",
                                      platforms: [.instagramReels, .tiktok, .linkedin, .x], postDays: [.monday, .tuesday, .wednesday, .thursday, .friday],
                                      durations: [15, 30], apps: ["Ambient"], goals: "Introduce reading with Mary.")
            var campaign = try store.create(name: "November", brief: brief)
            let topics = [("highlight", "Highlight a line", "Highlight *a line.*", "instagram_reels", "08:15", "Weekday commute: Reels' heaviest scroll before work."),
                          ("sources", "Every answer shows its source", "Every answer shows *where it came from.*", "linkedin", "12:10", "Lunch on LinkedIn: researchers read during the midday break."),
                          ("speaks-up", "Speaks at a pause", "It waits for *a pause.*", "tiktok", "19:30", "Evening TikTok, after work."),
                          ("on-device", "On your Mac", "Nothing has to *leave the Mac.*", "x", "09:05", "X's morning news hour.")]
            var days: [PlanResponse.Day] = []
            for (i, date) in brief.postDates.enumerated() {
                let t = topics[i % topics.count]
                days.append(PlanResponse.Day(index: i + 1, date: date, post_time_local: t.4, time_reason: t.5, platform: t.3, cross_post: [],
                                             topic_slug: "\(t.0)-\(i + 1)", title: t.1, duration: i % 3 == 2 ? 30 : 15, kicker: "Ambient, explained",
                                             headline: t.2, hook: "You read; Mary reads along.",
                                             scenes: [.init(at: 0, until: 6.35, recipe: "Desktop highlight", what: "A line is highlighted and its source appears."),
                                                      .init(at: 6.35, until: 13.4, recipe: "Code card", what: "The call that answers, grounded in your lane.")],
                                             recipes: ["Desktop highlight", "Code card"],
                                             caption: "Highlight a line and Ambient tells you where it came from. Every answer is cited, and it stays on your Mac.",
                                             hashtags: ["ambient", "reading", "mac"], cta: "ambient.rao.nyc"))
            }
            let plan = PlanResponse(summary: "A month that opens on reading with a highlighter, moves through citations, speaking up at a pause and the ⌃A panel, then the index underneath, and closes on why it stays on your Mac.",
                                    arc: ["Premise", "Reading along", "Sources", "On-device", "Finale"], sources: ["README.md", "https://ambient.rao.nyc"],
                                    cautions: ["Royalties framed as receipts, not payments", "Fictional names only"], days: days)
            campaign.plan = CampaignPlan(summary: plan.summary, arc: plan.arc, sources: plan.sources, cautions: plan.cautions, model: "claude-opus-5-5")
            campaign.days = PlanValidator.days(plan, brief: brief)
            try store.save(campaign)
            let paths = store.paths(campaign.id)
            let kit = workspace.projectFolder(project.slug).appendingPathComponent("kit")
            let sample = try String(contentsOf: URL(fileURLWithPath: args[4]), encoding: .utf8)
            for index in [1, 3] {
                var day = campaign.day(index)!
                if day.topic.duration != 15 { day.topic.duration = 15 }
                let a = paths.asset(day.stem)
                let html = PageVerifier.rewriteKitPaths(sample, pageFolder: a.folder, kitFolder: kit)
                try AtomicFile.write(html, to: a.page)
                let input = FinishInput(paths: paths, assetPaths: a, readAccess: workspace.projectFolder(project.slug), day: day, html: html,
                                        notes: AssetNotes(summary: "The highlighter, then the call that answers.", illustrative: ["“Morrow” and the bridge quote are fictional"],
                                                          softened: ["“stays on your Mac” rather than “never leaves”"], sources: ["README.md"]),
                                        altText: "A reader highlights a line about fog and its source appears beneath it; then the code that answers, and the Rao seal.",
                                        descriptions: [Cue(start: 0, end: 6.35, text: "A pearl card: a line is highlighted in gold and its source chip appears.", kind: .description),
                                                       Cue(start: 6.35, end: 13.4, text: "A dark code card shows the call that answers.", kind: .description),
                                                       Cue(start: 13.4, end: 15, text: "The Rao seal and the Ambient name.", kind: .description)])
                let stills = try await AssetFinisher.stills(input)
                var asset = try await AssetFinisher.finish(input, stills: stills)
                asset.reviewed = true
                day.asset = asset
                day.status = index == 1 ? .posted : .rendered
                if index == 1 { day.targets[0].postedAt = Date() }
                campaign.update(day)
                print("day \(index) built")
            }
            try store.save(campaign)
            print("fixture: \(paths.root.path)")
            print("campaign: \(campaign.id.uuidString)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("fixture failed: \(error)\n".utf8)); exit(1)
        }
    }
    app.run()
}

// `finish <campaign-dir> <sample-page.html> [song]`: the whole non-Claude build of one day.
if args.count >= 4, args[1] == "finish" {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    Task { @MainActor in
        do {
            let root = URL(fileURLWithPath: args[2], isDirectory: true)
            let paths = CampaignPaths(root: root.appendingPathComponent("campaigns/c"))
            let kit = root.appendingPathComponent("kit")
            try KitInstaller.install(into: kit, from: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../AdverbCore/Resources/Kit").standardizedFileURL)
            let topic = TopicBrief(slug: "highlight", title: "Highlight a line", duration: 15, kicker: "Ambient, explained",
                                   headline: "Highlight *a line.*", scenes: [], recipes: [])
            let day = CampaignDay(index: 1, date: "2026-11-02", postAt: Date(), postTimeLocal: "08:15", timeReason: "Commute.",
                                  targets: [PostTarget(platform: .instagramReels), PostTarget(platform: .x)], topic: topic,
                                  caption: "Highlight a line.", hashtags: ["ambient"], hook: "", cta: "")
            let a = paths.asset(day.stem)
            var html = try String(contentsOf: URL(fileURLWithPath: args[3]), encoding: .utf8)
            html = PageVerifier.rewriteKitPaths(html, pageFolder: a.folder, kitFolder: kit)
            try AtomicFile.write(html, to: a.page)
            print("page problems: \(PageVerifier.problems(html, duration: 15))")
            let info = try await PageRenderer.probe(page: a.page, readAccess: root)
            print("probe: DUR \(info.dur) scenes \(info.scenes) errors \(info.errors) missing fonts \(info.missingFonts)")
            var input = FinishInput(paths: paths, assetPaths: a, readAccess: root, day: day, html: html,
                                    notes: AssetNotes(summary: "Sample", illustrative: ["Morrow"]),
                                    altText: "A reader highlights a line about fog; the source chip appears beneath it.",
                                    descriptions: [Cue(start: 0, end: 6.35, text: "A card with a highlighted line and its source.", kind: .description),
                                                   Cue(start: 6.35, end: 13.4, text: "A code card shows the ask call.", kind: .description),
                                                   Cue(start: 13.4, end: 15, text: "The Rao seal and the Ambient name.", kind: .description)])
            var t0 = Date()
            let stills = try await AssetFinisher.stills(input)
            print(String(format: "stills: %d in %.1f s", stills.count, Date().timeIntervalSince(t0)))
            t0 = Date()
            var asset = try await AssetFinisher.finish(input, stills: stills)
            print(String(format: "finished in %.1f s", Date().timeIntervalSince(t0)))
            for r in asset.renders { print("  \(r.orientation.rawValue): \(r.report?.line ?? "") \(r.report?.warnings ?? [])") }
            for (k, c) in asset.a11y.captions.sorted(by: { $0.key < $1.key }) { print("  captions \(k): \(c.cueCount) cues, coverage \(c.coverage)") }
            for check in asset.a11y.checks { print("  check \(check.level.rawValue): \(check.message)") }
            if args.count >= 5 {
                let song = URL(fileURLWithPath: args[4])
                let full = try await BeatAnalyzer.shared.analyze(song)
                let inPoint = full.suggestedInPoint(for: 15)
                let grid = try await BeatAnalyzer.shared.analyzeWindow(song, inPoint: inPoint, duration: 15)
                let warp = Beatmap.warp(scenes: info.scenes, grid: grid, duration: 15, endAt: 13.4)
                print("beatmap: in-point \(inPoint), \(grid.bpm) BPM, knots \(warp.knots.map { String(format: "%.2f→%.2f", $0.page, $0.real) })")
                let kitPrefix = PageVerifier.relativePath(from: a.folder, to: kit)
                try AtomicFile.write(Beatmap.beatsScript(grid: grid, inPoint: inPoint, song: song.lastPathComponent), to: a.beats)
                html = Beatmap.withBeatScripts(html, kitPrefix: kitPrefix, beatsFile: a.beats.lastPathComponent)
                try AtomicFile.write(html, to: a.page)
                input.html = html
                input.previous = asset
                input.music = MusicChoice(songPath: song.path, songSHA: "", title: song.deletingPathExtension().lastPathComponent, bpm: grid.bpm,
                                          confidence: grid.confidence, inPoint: inPoint)
                input.mix = AudioMixSpec(song: song, inPoint: inPoint, duration: 15)
                input.warp = warp
                t0 = Date()
                asset = try await AssetFinisher.finish(input, stills: try await AssetFinisher.stills(input))
                print(String(format: "beatmapped in %.1f s; originals kept: %d", Date().timeIntervalSince(t0), asset.originals.count))
                for r in asset.renders { print("  \(r.orientation.rawValue): \(r.report?.line ?? "")") }
                let reverted = try AssetFinisher.revert(asset, paths: paths, assetPaths: a)
                print("reverted: music \(reverted.music == nil ? "cleared" : "kept"), renders \(reverted.renders.map(\.path))")
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("finish failed: \(error)\n".utf8)); exit(1)
        }
    }
    app.run()
}

let page = URL(fileURLWithPath: args[1]).standardizedFileURL
let orientation: Orientation = args[2].uppercased() == "L" ? .landscape : .portrait
let out = URL(fileURLWithPath: args[3], isDirectory: true)
let frameLimit = args.firstIndex(of: "--frames").flatMap { Int(args[$0 + 1]) }
let scale = args.contains("--supersample") ? 2 : 1
let mbps = args.firstIndex(of: "--bitrate").flatMap { Int(args[$0 + 1]) } ?? 12

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

Task { @MainActor in
    do {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let readAccess = page.deletingLastPathComponent()
        // 1. Frames as PNGs, timed.
        let source = WebFrameSource(orientation: orientation, scale: scale)
        let loadStart = Date()
        let info = try await source.load(page: page, readAccess: readAccess)
        print(String(format: "loaded in %.2f s · DUR %.1f · dpr %.1f · scenes %@", Date().timeIntervalSince(loadStart), info.dur, info.dpr, info.scenes.description))
        print("fonts: " + info.fonts.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))
        if !info.errors.isEmpty { print("page errors: \(info.errors)") }
        let count = frameLimit ?? Int(info.dur * 30)
        var times: [Double] = []
        for i in stride(from: 0, to: count, by: max(1, count / 6)) {
            let t0 = Date()
            var image = try await source.frame(at: "\(i)/30")
            let snap = Date().timeIntervalSince(t0)
            if scale > 1, let s = ImageScaler.scale(image, width: orientation.width, height: orientation.height) { image = s }
            times.append(snap)
            try ImageFiles.writePNG(image, to: out.appendingPathComponent(String(format: "frame-%@-%04d.png", orientation.letter, i)))
            print(String(format: "frame %4d: %d×%d in %.0f ms", i, image.width, image.height, snap * 1000))
        }
        source.close()
        // 2. The MP4, through the real path.
        let mp4 = out.appendingPathComponent("probe-\(orientation.rawValue).mp4")
        let start = Date()
        let result = try await PageRenderer.render(page: page, readAccess: readAccess, orientation: orientation, to: mp4,
                                                   options: RenderOptions(scale: scale, encoder: EncoderSettings(bitrate: mbps * 1_000_000)),
                                                   duration: frameLimit.map { Double($0) / 30 })
        let elapsed = Date().timeIntervalSince(start)
        print(String(format: "rendered %d frames in %.1f s (%.0f ms/frame)", result.report.frameCount, elapsed, elapsed * 1000 / Double(max(1, result.report.frameCount))))
        print("report: \(result.report.line)")
        if !result.report.warnings.isEmpty { print("warnings: \(result.report.warnings)") }
        let samples = result.captions.prefix(400).map { s in "\(String(format: "%5.2f", s.t))  " + s.items.map { "[\($0.kind)] \($0.text)" }.joined(separator: " | ") }
        try samples.joined(separator: "\n").write(to: out.appendingPathComponent("captions-\(orientation.rawValue).txt"), atomically: true, encoding: .utf8)
        print("captions sampled: \(result.captions.count)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("probe failed: \(error)\n".utf8))
        exit(1)
    }
}
app.run()
