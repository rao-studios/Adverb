//
//  Toolchain.swift
//  AdverbRender
//
//  WHAT: What is on this Mac for the optional Chrome renderer (the skill's own render.py): python3
//        with Playwright, Chrome or Playwright's Chromium, ffmpeg with libx264. The native renderer
//        needs none of it.
//  PIN:  A GUI app starts with a bare PATH: look in Homebrew's and pyenv's folders, then ask a login
//        shell.
//

import Foundation

public enum Toolchain {
    public struct Found: Sendable, Equatable {
        public var name: String
        public var path: String?
        public var detail: String
    }

    static let folders = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "\(NSHomeDirectory())/.pyenv/shims", "\(NSHomeDirectory())/.local/bin"]

    public static func locate(_ tool: String) -> String? {
        for folder in folders {
            let path = "\(folder)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        let out = run("/bin/zsh", ["-lc", "command -v \(tool)"], timeout: 5)
        let path = out.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.status == 0 && !path.isEmpty ? path : nil
    }

    /// The python3 that can import Playwright: the login shell's first (pyenv), then the usual
    /// folders. Nil when none can; then the first python3 found is reported as lacking it.
    public static func playwrightPython() -> String? {
        var candidates: [String] = []
        let shell = run("/bin/zsh", ["-lc", "command -v python3"], timeout: 5).output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !shell.isEmpty { candidates.append(shell) }
        candidates += folders.map { "\($0)/python3" }
        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted && FileManager.default.isExecutableFile(atPath: path) {
            if run(path, ["-I", "-c", "import playwright"], timeout: 15).status == 0 { return path }
        }
        return nil
    }

    /// The checks, each with what is there and the command that fixes it.
    public static func check() -> [(id: String, title: String, ok: Bool?, detail: String, fix: String?)] {
        var out: [(String, String, Bool?, String, String?)] = []
        out.append(("native", "Native renderer", true, "WebKit and AVFoundation, built in", nil))
        let withPlaywright = playwrightPython()
        let python = withPlaywright ?? locate("python3")
        out.append(("python", "python3", python != nil, python ?? "not found", python == nil ? "brew install python@3.12" : nil))
        if let python {
            out.append(("playwright", "Playwright for Python", withPlaywright != nil, withPlaywright != nil ? "installed (\(python))" : "not installed",
                        withPlaywright != nil ? nil : "\(python) -m pip install playwright"))
        }
        let chrome = FileManager.default.fileExists(atPath: "/Applications/Google Chrome.app")
        out.append(("chrome", "Google Chrome", chrome, chrome ? "/Applications/Google Chrome.app" : "not installed",
                    chrome ? nil : "python3 -m playwright install chromium"))
        if let ffmpeg = locate("ffmpeg") {
            let encoders = run(ffmpeg, ["-hide_banner", "-encoders"], timeout: 10).output
            let x264 = encoders.contains("libx264")
            out.append(("ffmpeg", "ffmpeg", x264, x264 ? "\(ffmpeg) with libx264" : "\(ffmpeg) without libx264", x264 ? nil : "brew reinstall ffmpeg"))
        } else {
            out.append(("ffmpeg", "ffmpeg", false, "not found (only the skill's render.py needs it)", "brew install ffmpeg"))
        }
        return out
    }

    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate(); return (-1, "timed out") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
