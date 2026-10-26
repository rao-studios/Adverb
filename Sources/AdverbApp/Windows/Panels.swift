//
//  Panels.swift
//  Adverb
//
//  WHAT: Choosing folders and files: the working directory (the T9), a project's context folder,
//        the music folder, a song.
//

import AppKit
import UniformTypeIdentifiers

@MainActor
enum Panels {
    static func chooseFolder(title: String, prompt: String, message: String, start: URL? = nil, canCreate: Bool = true) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.message = message
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = canCreate
        panel.allowsMultipleSelection = false
        if let start { panel.directoryURL = start }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseSongs() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Add songs"
        panel.prompt = "Add"
        panel.message = "Choose songs to cut assets to. Adverb reads them where they are."
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls.filter { FileManager.default.fileExists(atPath: $0.path) })
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
