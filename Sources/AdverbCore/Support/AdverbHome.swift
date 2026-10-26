//
//  AdverbHome.swift
//  AdverbCore
//
//  WHAT: Where Adverb keeps what is the person's and not a project's: settings, under AII_HOME
//        (default `~/.rao`) at apps/adverb, beside Craft's, Ambient's and Veil's.
//  PIN:  The projects and their assets never live here: they live in the working directory the
//        person chose (the T9). The API key never lives here either: it is in the Keychain.
//

import Foundation

public enum AdverbHome {
    public static func root(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let home = environment["AII_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".rao", isDirectory: true)
    }

    public static func app(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        root(environment: environment).appendingPathComponent("apps/adverb", isDirectory: true)
    }

    public static var settingsFile: URL { app().appendingPathComponent("settings.json") }

    /// Waveforms and beat grids: derived, re-made when missing.
    public static var caches: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nyc.rao.adverb", isDirectory: true)
    }
}
