//
//  AdverbAppDelegate.swift
//  Adverb
//
//  WHAT: Launch: the faces, the menu, the root's boot, the main window. Quit: cancel what runs.
//  IN:   AdverbRuntimeRoot
//  OUT:  MainWindowController, SettingsWindowController, MainMenu
//

import AdverbRuntime
import AppKit
import Granite

@MainActor
final class AdverbAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        GraniteLogger.currentLevel = .error
        FontRegistry.registerBundled()
        MainMenu.install()
        MainWindowController.shared.showWindow(nil)
        Task { await AdverbRuntimeRoot.shared.boot() }
        NSApp.activate()
        #if DEBUG
        SnapshotProbe.run()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowController.shared.showWindow(nil) }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let root = AdverbRuntimeRoot.shared
        let busy = root.generation.state.active
        guard !busy.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop \(busy.count) running \(busy.count == 1 ? "job" : "jobs") and quit?"
        alert.informativeText = "Days that finished are saved. A day being built stops, and builds again from the start next time."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        for run in busy { root.cancelRun(run.key) }
        return .terminateNow
    }

    // MARK: Menu actions

    @objc func showSettings(_ sender: Any?) { SettingsWindowController.show() }
    @objc func showAbout(_ sender: Any?) { SettingsWindowController.show(section: .about) }
    @objc func newProject(_ sender: Any?) { MainWindowController.shared.selection.sheet = .newProject; MainWindowController.shared.showWindow(nil) }

    @objc func newCampaign(_ sender: Any?) {
        let selection = MainWindowController.shared.selection
        guard let slug = selection.projectSlug ?? AdverbRuntimeRoot.shared.projects.state.projects.first?.slug else { return }
        selection.sheet = .newCampaign(slug)
    }

    @objc func revealAdverbFolder(_ sender: Any?) {
        guard let root = AdverbRuntimeRoot.shared.workspace?.root else { return }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    @objc func buildRemaining(_ sender: Any?) {
        let s = MainWindowController.shared.selection
        guard let slug = s.projectSlug, let id = s.campaignID else { return }
        AdverbRuntimeRoot.shared.buildAll(slug, id, onlyMissing: true)
    }

    @objc func exportCampaign(_ sender: Any?) {
        let s = MainWindowController.shared.selection
        guard let slug = s.projectSlug, let id = s.campaignID else { return }
        Task {
            let urls = await AdverbRuntimeRoot.shared.export(slug, id)
            if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        }
    }

    @objc func toggleRuns(_ sender: Any?) { MainWindowController.shared.selection.showRuns.toggle() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let s = MainWindowController.shared.selection
        switch item.action {
        case #selector(buildRemaining(_:)), #selector(exportCampaign(_:)): return s.campaignID != nil
        case #selector(newCampaign(_:)): return !AdverbRuntimeRoot.shared.projects.state.projects.isEmpty
        default: return true
        }
    }
}

extension AdverbAppDelegate: NSMenuItemValidation {}
