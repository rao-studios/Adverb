//
//  MainWindowController.swift
//  Adverb
//
//  WHAT: The one main window: the gate (key, working directory, drive) until the app is ready,
//        then projects and campaigns beside the calendar.
//

import AdverbRuntime
import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MainWindowController()
    let selection = DeskSelection()

    private init() {
        let size = AdverbLayout.fitted(AdverbLayout.main.ideal)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Adverb"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .adverbPage
        window.appearance = NSAppearance(named: .aqua)
        window.contentMinSize = AdverbLayout.main.floor
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.hostAdverb(Root(selection: selection).adverbRoot())
        window.restoreFrame(named: "AdverbMain", ideal: AdverbLayout.main.ideal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var current: SettingsWindowController?
    let navigation = SettingsNavigation()

    static func show(section: SettingsSection? = nil) {
        let controller = current ?? SettingsWindowController()
        current = controller
        if let section { controller.navigation.section = section }
        NSApp.activate()
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: AdverbLayout.fitted(AdverbLayout.settings.ideal)),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .adverbPage
        window.appearance = NSAppearance(named: .aqua)
        window.contentMinSize = AdverbLayout.settings.floor
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.hostAdverb(Settings(navigation: navigation).adverbRoot())
        window.restoreFrame(named: "AdverbSettings", ideal: AdverbLayout.settings.ideal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func windowWillClose(_ notification: Notification) { Self.current = nil }
}
