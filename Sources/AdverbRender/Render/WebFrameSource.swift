//
//  WebFrameSource.swift
//  AdverbRender
//
//  WHAT: One kit page in an offscreen WKWebView, seeked frame by frame and snapshotted at exactly
//        the asset's pixel size (or twice it, for supersampling).
//  IN:   a page.html and the folder it may read (the project folder, which holds kit/).
//  OUT:  CGImages, sRGB, W×H; the page's own facts (PageInfo); the visible text per frame.
//  PIN:  macOS `takeSnapshot` is a software paint of the render tree in the web process, so the
//        view needs a window (for a stable backing scale) but never needs to be on screen: the
//        window is borderless, far off any display, never ordered front. `snapshotWidth` is in
//        points and the bitmap comes back at the window's backing scale, so the width asked for is
//        W ÷ that scale, and the result is checked to be exactly W pixels wide.
//

import AppKit
import AdverbCore
import Foundation
import WebKit

public struct PageInfo: Sendable, Equatable, Codable {
    public var dur: Double
    public var scenes: [Double]
    public var dpr: Double
    public var fonts: [String: Bool]
    public var errors: [String]
    public var title: String

    public var missingFonts: [String] { fonts.filter { !$0.value }.map(\.key).sorted() }
}

public enum RenderError: Error, CustomStringConvertible {
    case loadTimedOut(URL)
    case loadFailed(String)
    case notAKitPage(String)
    case badSnapshot(String)
    case writer(String)
    case cancelled

    public var description: String {
        switch self {
        case .loadTimedOut(let url): "The page did not become ready in time: \(url.lastPathComponent)"
        case .loadFailed(let message): "The page failed to load: \(message)"
        case .notAKitPage(let message): "Not a kit page: \(message)"
        case .badSnapshot(let message): "A frame could not be captured: \(message)"
        case .writer(let message): "The video could not be written: \(message)"
        case .cancelled: "Cancelled"
        }
    }
}

@MainActor
public final class WebFrameSource: NSObject, WKNavigationDelegate {
    public let orientation: Orientation
    /// 1, or 2 to paint each frame at twice the size before it is scaled down.
    public let scale: Int
    private let window: NSWindow
    private let webView: WKWebView
    private var navigation: CheckedContinuation<Void, Error>?

    public var width: Int { orientation.width }
    public var height: Int { orientation.height }

    public init(orientation: Orientation, scale: Int = 1) {
        self.orientation = orientation
        self.scale = max(1, min(scale, 2))
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.userContentController.addUserScript(WKUserScript(source: Harness.documentStart, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let frame = NSRect(x: 0, y: 0, width: orientation.width, height: orientation.height)
        webView = WKWebView(frame: frame, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        window = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: frame.width, height: frame.height),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        super.init()
        webView.navigationDelegate = self
    }

    /// Loads `page` with `?o=P|L` (and any extra query), and waits for the kit to boot and its
    /// faces to load.
    public func load(page: URL, readAccess: URL, query: [URLQueryItem] = [], timeout: TimeInterval = 20) async throws -> PageInfo {
        var components = URLComponents(url: page, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "o", value: orientation.letter)] + query
        guard let url = components.url else { throw RenderError.loadFailed("bad page URL") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigation = continuation
            webView.loadFileURL(url, allowingReadAccessTo: readAccess)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let ready = try? await webView.evaluateJavaScript(Harness.ready) as? Int, ready == 1 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard (try? await webView.evaluateJavaScript(Harness.ready) as? Int) == 1 else { throw RenderError.loadTimedOut(page) }
        _ = try? await webView.evaluateJavaScript("document.fonts.ready.then(function(){return 1})")
        let json = try await webView.evaluateJavaScript(Harness.probe) as? String ?? "{}"
        let info = try JSONDecoder().decode(PageInfo.self, from: Data(json.utf8))
        guard info.dur > 0 else { throw RenderError.notAKitPage("window.DUR is not set") }
        return info
    }

    /// The frame at `t` seconds: seek, flush layout, snapshot.
    public func frame(at t: String) async throws -> CGImage {
        _ = try await webView.evaluateJavaScript("seek(\(t)); document.body.offsetHeight; 0")
        return try await snapshot()
    }

    public func seek(_ t: String) async throws {
        _ = try await webView.evaluateJavaScript("seek(\(t)); document.body.offsetHeight; 0")
    }

    /// The text on screen now (after a seek).
    public func visibleText() async -> [CaptionItem] {
        guard let json = try? await webView.evaluateJavaScript(Harness.cues) as? String else { return [] }
        return (try? JSONDecoder().decode([CaptionItem].self, from: Data(json.utf8))) ?? []
    }

    public func evaluate(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    public func snapshot() async throws -> CGImage {
        let backing = max(window.backingScaleFactor, 1)
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: width, height: height)
        config.afterScreenUpdates = true
        let target = width * scale
        config.snapshotWidth = NSNumber(value: Double(target) / Double(backing))
        let image = try await webView.takeSnapshot(configuration: config)
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { throw RenderError.badSnapshot("no bitmap") }
        if cg.width == target { return cg }
        // A scale the window reported wrongly: draw it to size rather than fail the render.
        guard let fixed = ImageScaler.scale(cg, width: target, height: height * scale) else {
            throw RenderError.badSnapshot("\(cg.width)×\(cg.height), wanted \(target)")
        }
        return fixed
    }

    public func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        window.contentView = nil
        window.close()
    }

    // MARK: WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.navigation?.resume(); self.navigation = nil
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.navigation?.resume(throwing: RenderError.loadFailed(error.localizedDescription)); self.navigation = nil
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.navigation?.resume(throwing: RenderError.loadFailed(error.localizedDescription)); self.navigation = nil
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        self.navigation?.resume(throwing: RenderError.loadFailed("the web process ended")); self.navigation = nil
    }
}
