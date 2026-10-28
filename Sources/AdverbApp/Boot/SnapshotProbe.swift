//
//  SnapshotProbe.swift
//  Adverb
//
//  WHAT: Debug builds only: `--adverb-select <slug> <campaign> [day]` opens a campaign (and a day)
//        at launch; `--adverb-snapshot <file.png>` writes the main window to a PNG once it settles
//        and quits; `--adverb-settings <section>` opens Settings at a page first. How the UI is
//        checked without a person at the screen.
//

#if DEBUG
import AdverbRuntime
import AppKit

@MainActor
enum SnapshotProbe {
    static func run() {
        let args = CommandLine.arguments
        guard args.contains(where: { $0.hasPrefix("--adverb-") }) else { return }
        Task { @MainActor in
            if let i = args.firstIndex(of: "--adverb-size"), args.count > i + 1 {
                let parts = args[i + 1].split(separator: "x").compactMap { Double($0) }
                if parts.count == 2, let window = MainWindowController.shared.window {
                    window.contentMinSize = NSSize(width: 400, height: 300)
                    window.setFrame(NSRect(x: 0, y: 0, width: parts[0], height: parts[1]), display: true)
                }
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if let i = args.firstIndex(of: "--adverb-select"), args.count > i + 2, let id = UUID(uuidString: args[i + 2]) {
                let selection = MainWindowController.shared.selection
                selection.select(campaign: id, in: args[i + 1])
                if args.count > i + 3, let day = Int(args[i + 3]) { selection.dayIndex = day }
            }
            if let i = args.firstIndex(of: "--adverb-orientation"), args.count > i + 1 {
                MainWindowController.shared.selection.orientation = args[i + 1]
            }
            if let i = args.firstIndex(of: "--adverb-sheet"), args.count > i + 1 {
                let s = MainWindowController.shared.selection
                switch args[i + 1] {
                case "new-project": s.sheet = .newProject
                case "new-campaign": if let slug = s.projectSlug { s.sheet = .newCampaign(slug) }
                case "manage": if let slug = s.projectSlug { s.sheet = .manageProject(slug) }
                case "music": if let slug = s.projectSlug, let c = s.campaignID, let d = s.dayIndex { s.sheet = .music(slug: slug, campaign: c, day: d) }
                case "campaign-voice": if let slug = s.projectSlug, let c = s.campaignID { s.sheet = .campaignVoice(slug: slug, campaign: c) }
                case "voice": if let slug = s.projectSlug, let c = s.campaignID, let d = s.dayIndex { s.sheet = .voice(slug: slug, campaign: c, day: d) }
                default: break
                }
            }
            if args.contains("--adverb-plan"), let slug = MainWindowController.shared.selection.projectSlug,
               let id = MainWindowController.shared.selection.campaignID {
                AdverbRuntimeRoot.shared.plan(slug, id)
                try? await Task.sleep(nanoseconds: 6_000_000_000)
            }
            var window: NSWindow? = MainWindowController.shared.window
            if let i = args.firstIndex(of: "--adverb-settings"), args.count > i + 1, let section = SettingsSection(rawValue: args[i + 1]) {
                SettingsWindowController.show(section: section)
                window = NSApp.windows.first { $0.title == "Settings" }
            }
            guard let i = args.firstIndex(of: "--adverb-snapshot"), args.count > i + 1 else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let target = window?.attachedSheet ?? window
            guard let view = target?.contentView?.superview ?? target?.contentView,
                  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(2) }
            // At 2×, for the README.
            rep.size = view.bounds.size
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
    }
}
#endif
