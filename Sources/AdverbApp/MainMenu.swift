//
//  MainMenu.swift
//  Adverb
//
//  WHAT: The main menu, by hand (Craft's): Adverb, File, Edit, Campaign, View, Window.
//

import AppKit

enum MainMenu {
    struct Item {
        let title: String?
        let action: Selector?
        let key: String
        var modifiers: NSEvent.ModifierFlags = [.command]
        static let separator = Item(title: nil, action: nil, key: "")
    }

    static let appItems: [Item] = [
        Item(title: "About Adverb", action: #selector(AdverbAppDelegate.showAbout(_:)), key: ""), .separator,
        Item(title: "Settings…", action: #selector(AdverbAppDelegate.showSettings(_:)), key: ","), .separator,
        Item(title: "Hide Adverb", action: #selector(NSApplication.hide(_:)), key: "h"),
        Item(title: "Quit Adverb", action: #selector(NSApplication.terminate(_:)), key: "q"),
    ]

    static let fileItems: [Item] = [
        Item(title: "New Project…", action: #selector(AdverbAppDelegate.newProject(_:)), key: "n"),
        Item(title: "New Campaign…", action: #selector(AdverbAppDelegate.newCampaign(_:)), key: "n", modifiers: [.command, .shift]), .separator,
        Item(title: "Reveal Adverb Folder", action: #selector(AdverbAppDelegate.revealAdverbFolder(_:)), key: "r", modifiers: [.command, .shift]), .separator,
        Item(title: "Close", action: #selector(NSWindow.performClose(_:)), key: "w"),
    ]

    static let campaignItems: [Item] = [
        Item(title: "Build Remaining Days", action: #selector(AdverbAppDelegate.buildRemaining(_:)), key: "b"),
        Item(title: "Export the Month…", action: #selector(AdverbAppDelegate.exportCampaign(_:)), key: "e", modifiers: [.command, .shift]),
    ]

    static func install() {
        let main = NSMenu()
        main.addItem(submenu("Adverb", appItems))
        main.addItem(submenu("File", fileItems))
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("", "", ""), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                     ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            if title.isEmpty { edit.addItem(.separator()); continue }
            edit.addItem(withTitle: title, action: Selector((action)), keyEquivalent: key)
        }
        let editItem = NSMenuItem(); editItem.submenu = edit; main.addItem(editItem)
        main.addItem(submenu("Campaign", campaignItems))
        let view = NSMenu(title: "View")
        view.addItem(withTitle: "Show or Hide Runs", action: #selector(AdverbAppDelegate.toggleRuns(_:)), keyEquivalent: "j")
        let sidebar = view.addItem(withTitle: "Toggle Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
        sidebar.keyEquivalentModifierMask = [.command, .control]
        let viewItem = NSMenuItem(); viewItem.submenu = view; main.addItem(viewItem)
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let windowItem = NSMenuItem(); windowItem.submenu = window; main.addItem(windowItem)
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }

    static func submenu(_ title: String, _ items: [Item]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        for item in items {
            guard let t = item.title else { menu.addItem(.separator()); continue }
            let added = menu.addItem(withTitle: t, action: item.action, keyEquivalent: item.key)
            added.keyEquivalentModifierMask = item.modifiers
        }
        let host = NSMenuItem()
        host.submenu = menu
        return host
    }
}
