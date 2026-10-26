//
//  ChromeRenderer.swift
//  AdverbRender
//
//  WHAT: The optional renderer: Chrome paints each frame through Playwright (the kit's
//        render-frames.py), and the frames stream back losslessly into the same encoder the native
//        renderer uses, with the same audio and the same caption samples. For parity with assets
//        made by the skill's own render.py, or a page WebKit paints differently.
//  PIN:  Needs python3 with Playwright, and Chrome (or Playwright's Chromium). No ffmpeg.
//

import AdverbCore
import CoreGraphics
import Foundation
import ImageIO

public enum ChromeRenderer {
    public enum Failure: Error, CustomStringConvertible {
        case toolMissing(String)
        case script(String)
        public var description: String {
            switch self {
            case .toolMissing(let t): "\(t) was not found. Settings › Rendering shows how to install it."
            case .script(let m): "Chrome renderer: \(m)"
            }
        }
    }

    struct Record { let kind: UInt8; let payload: Data }

    public static func render(page: URL, kit: URL, orientation: Orientation, to destination: URL, options: RenderOptions,
                              duration: Double, progress: @escaping @Sendable (Double) -> Void,
                              isCancelled: @escaping @Sendable () -> Bool) async throws -> RenderOutput {
        let started = Date()
        var args = [page.path, orientation.letter, "frames", "--cues", String(options.captionEvery), "--scale", String(options.scale)]
        if let warp = options.warp, !warp.isIdentity { args += ["--warp", warp.knots.map { "\($0.page):\($0.real)" }.joined(separator: ",")] }
        let fps = Int(options.encoder.fps)
        let total = Int((duration * Double(fps)).rounded())
        let samples = try await AudioSampleSource.samples(duration: Double(total) / Double(fps), mix: options.mix)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("adverb-\(UUID().uuidString).mp4")
        let writer = try MP4Writer(url: temp, width: orientation.width, height: orientation.height, settings: options.encoder, audio: samples)
        var info = PageInfo(dur: duration, scenes: [], dpr: 1, fonts: [:], errors: [], title: "")
        var captions: [CaptionSample] = []
        var frames = 0
        do {
            for try await record in stream(script: kit.appendingPathComponent("render-frames.py"), args: args) {
                if isCancelled() { throw RenderError.cancelled }
                switch record.kind {
                case UInt8(ascii: "I"):
                    if let json = try? JSONValue.parse(record.payload) {
                        info.dur = json["dur"]?.doubleValue ?? duration
                        info.dpr = json["dpr"]?.doubleValue ?? 1
                        info.scenes = json["scenes"]?.arrayValue?.compactMap(\.doubleValue) ?? []
                    }
                case UInt8(ascii: "F"):
                    guard frames < total, var image = decode(record.payload) else { continue }
                    if image.width != orientation.width, let s = ImageScaler.scale(image, width: orientation.width, height: orientation.height) { image = s }
                    try await writer.append(image)
                    frames += 1
                    if frames % 10 == 0 { progress(Double(frames) / Double(total)) }
                case UInt8(ascii: "C"):
                    if let sample = try? JSONDecoder().decode(CaptionSample.self, from: record.payload) { captions.append(sample) }
                case UInt8(ascii: "E"):
                    throw Failure.script(JSONValue.object(inText: record.payload) ?? "the script failed")
                default:
                    break
                }
            }
            guard frames == total else { throw Failure.script("\(frames) frames came back, \(total) were wanted") }
            try await writer.finish()
        } catch {
            writer.cancel()
            throw error
        }
        try AtomicFile.replace(destination, with: temp)
        try? FileManager.default.removeItem(at: temp)
        progress(1)
        let report = try await RenderInspector.inspect(destination, expecting: (duration, orientation), renderSeconds: Date().timeIntervalSince(started))
        return RenderOutput(report: report, info: info, captions: captions)
    }

    public static func stills(page: URL, kit: URL, orientation: Orientation, times: [Double], to urls: [URL], warp: TimeWarp?) async throws {
        var args = [page.path, orientation.letter, "stills", "--times", times.map { String($0) }.joined(separator: ",")]
        if let warp, !warp.isIdentity { args += ["--warp", warp.knots.map { "\($0.page):\($0.real)" }.joined(separator: ",")] }
        var i = 0
        for try await record in stream(script: kit.appendingPathComponent("render-frames.py"), args: args) {
            if record.kind == UInt8(ascii: "E") { throw Failure.script(JSONValue.object(inText: record.payload) ?? "the script failed") }
            guard record.kind == UInt8(ascii: "F"), i < urls.count, let image = decode(record.payload) else { continue }
            try ImageFiles.writeJPEG(image, to: urls[i], quality: 0.9)
            i += 1
        }
    }

    static func decode(_ png: Data) -> CGImage? {
        CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    /// Runs the script and yields its records as they arrive.
    static func stream(script: URL, args: [String]) -> AsyncThrowingStream<Record, Error> {
        AsyncThrowingStream { continuation in
            guard let python = Toolchain.playwrightPython() else { continuation.finish(throwing: Failure.toolMissing("Python with Playwright")); return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = ["-I", script.path] + args
            var env = ProcessInfo.processInfo.environment
            env["ADVERB_HARNESS"] = Harness.documentStart
            env["ADVERB_CUES_JS"] = Harness.cues
            process.environment = env
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            let reader = Task.detached {
                let handle = out.fileHandleForReading
                func read(_ n: Int) -> Data? {
                    var data = Data()
                    while data.count < n {
                        let chunk = handle.readData(ofLength: n - data.count)
                        if chunk.isEmpty { return nil }
                        data.append(chunk)
                    }
                    return data
                }
                while let head = read(5) {
                    let kind = head[head.startIndex]
                    let length = head.dropFirst().reduce(0) { ($0 << 8) | Int($1) }
                    guard let payload = read(length) else { break }
                    continuation.yield(Record(kind: kind, payload: payload))
                }
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    continuation.finish(throwing: Failure.script(String(message.suffix(400))))
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in reader.cancel(); if process.isRunning { process.terminate() } }
            do { try process.run() } catch { continuation.finish(throwing: Failure.script("\(error)")) }
        }
    }
}

extension JSONValue {
    /// `{"error": "…"}` as its message.
    static func object(inText data: Data) -> String? { (try? JSONValue.parse(data))?["error"]?.stringValue }
}
