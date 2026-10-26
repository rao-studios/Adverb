//
//  PageRenderer.swift
//  AdverbRender
//
//  WHAT: A kit page to an MP4 (one orientation), to stills, and to what was on screen when — the
//        native render path. Frames are seek(i/30) → snapshot → encoder; the audio is silence or
//        the song; a time warp, when given, plays the page to the beat.
//  OUT:  the MP4 (written to a temporary file, then copied into place), its RenderReport, the
//        page's facts, and the caption samples.
//  PIN:  Without a warp, the page is sought at the literal `i/30`, the same IEEE value render.py
//        computes as `i / FPS`, so a frame here is the frame the skill's pipeline would have
//        shown. Cancellation is checked every frame.
//

import AdverbCore
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct RenderOptions: Sendable, Equatable {
    public var scale: Int
    public var encoder: EncoderSettings
    public var mix: AudioMixSpec?
    public var warp: TimeWarp?
    /// Sample the visible text every `captionEvery` frames (0: never).
    public var captionEvery: Int
    /// Extra query items for the page (`cc=1`, …).
    public var query: [URLQueryItem]

    public init(scale: Int = 1, encoder: EncoderSettings = .init(), mix: AudioMixSpec? = nil, warp: TimeWarp? = nil,
                captionEvery: Int = 3, query: [URLQueryItem] = []) {
        self.scale = scale; self.encoder = encoder; self.mix = mix; self.warp = warp; self.captionEvery = captionEvery; self.query = query
    }
}

public struct RenderOutput: Sendable {
    public var report: RenderReport
    public var info: PageInfo
    public var captions: [CaptionSample]
}

@MainActor
public enum PageRenderer {

    public static func render(page: URL, readAccess: URL, orientation: Orientation, to destination: URL,
                              options: RenderOptions = .init(), duration overrideDuration: Double? = nil,
                              progress: @escaping @Sendable (Double) -> Void = { _ in },
                              isCancelled: @escaping @Sendable () -> Bool = { Task.isCancelled }) async throws -> RenderOutput {
        let started = Date()
        let source = WebFrameSource(orientation: orientation, scale: options.scale)
        defer { source.close() }
        let info = try await source.load(page: page, readAccess: readAccess, query: options.query)
        let duration = overrideDuration ?? info.dur
        let fps = Int(options.encoder.fps)
        let total = Int((duration * Double(fps)).rounded())
        let samples = try await AudioSampleSource.samples(duration: Double(total) / Double(fps), mix: options.mix)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("adverb-\(UUID().uuidString).mp4")
        let writer = try MP4Writer(url: temp, width: orientation.width, height: orientation.height, settings: options.encoder, audio: samples)
        var captions: [CaptionSample] = []
        do {
            for i in 0..<total {
                if isCancelled() { throw RenderError.cancelled }
                let t = seekTime(i, fps: fps, warp: options.warp)
                var image = try await source.frame(at: t)
                if options.scale > 1, let scaled = ImageScaler.scale(image, width: orientation.width, height: orientation.height) {
                    image = scaled
                }
                try await writer.append(image)
                if options.captionEvery > 0, i % options.captionEvery == 0 {
                    captions.append(CaptionSample(t: Double(i) / Double(fps), items: await source.visibleText()))
                }
                if i % 10 == 0 { progress(Double(i) / Double(total)) }
            }
            try await writer.finish()
        } catch {
            writer.cancel()
            throw error
        }
        try AtomicFile.replace(destination, with: temp)
        try? FileManager.default.removeItem(at: temp)
        progress(1)
        let report = try await RenderInspector.inspect(destination, expecting: (duration, orientation),
                                                       renderSeconds: Date().timeIntervalSince(started))
        return RenderOutput(report: report, info: info, captions: captions)
    }

    /// JPEG stills at `times` (seconds), one per URL.
    public static func stills(page: URL, readAccess: URL, orientation: Orientation, times: [Double], to urls: [URL],
                              scale: Int = 1, warp: TimeWarp? = nil) async throws -> PageInfo {
        let source = WebFrameSource(orientation: orientation, scale: scale)
        defer { source.close() }
        let info = try await source.load(page: page, readAccess: readAccess)
        for (t, url) in zip(times, urls) {
            let pageT = warp.map { String(format: "%.6f", $0.pageTime(forReal: t)) } ?? String(format: "%.6f", t)
            var image = try await source.frame(at: pageT)
            if scale > 1, let scaled = ImageScaler.scale(image, width: orientation.width, height: orientation.height) { image = scaled }
            try ImageFiles.writeJPEG(image, to: url, quality: 0.9)
        }
        return info
    }

    /// Loads the page and reports what it is, without rendering.
    public static func probe(page: URL, readAccess: URL, orientation: Orientation = .portrait) async throws -> PageInfo {
        let source = WebFrameSource(orientation: orientation)
        defer { source.close() }
        let info = try await source.load(page: page, readAccess: readAccess)
        // Seek a few instants: a page that throws mid-timeline (a hidden element measured in seek)
        // fails here, not 400 frames into a render.
        for t in [0, info.dur * 0.25, info.dur * 0.5, info.dur * 0.75, max(0, info.dur - 0.05)] {
            _ = try await source.evaluate("try{seek(\(t));0}catch(e){window.__ADVERB__.errors.push(String(e.message||e));0}")
        }
        let errors = (try? await source.evaluate("JSON.stringify(window.__ADVERB__.errors)") as? String)
            .flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []
        var out = info
        out.errors = errors
        return out
    }

    static func seekTime(_ i: Int, fps: Int, warp: TimeWarp?) -> String {
        guard let warp, !warp.isIdentity else { return "\(i)/\(fps)" }
        return String(format: "%.6f", warp.pageTime(forReal: Double(i) / Double(fps)))
    }
}
