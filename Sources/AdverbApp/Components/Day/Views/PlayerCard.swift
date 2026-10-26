//
//  PlayerCard.swift
//  Adverb
//
//  WHAT: The asset playing, in the orientation chosen, with its closed captions drawn from its own
//        WebVTT file, and its render's report underneath.
//

import AVKit
import AdverbCore
import SwiftUI

struct PlayerCard: View {
    let asset: Asset
    let paths: CampaignPaths
    @Bindable var selection: DeskSelection
    @State private var player = CaptionedPlayer()
    @AppStorage("player.captions") private var captionsOn = true
    /// The asset's still until play is pressed: the day reads at a glance, and nothing decodes until asked.
    @State private var showPoster = true

    var orientation: Orientation { Orientation(rawValue: selection.orientation) ?? .portrait }

    var body: some View {
        AdverbCard(padding: .layer3) {
            VStack(alignment: .leading, spacing: .layer2) {
                HStack {
                    Picker("", selection: $selection.orientation) {
                        Text("Portrait").tag(Orientation.portrait.rawValue)
                        Text("Landscape").tag(Orientation.landscape.rawValue)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Spacer()
                    Toggle("CC", isOn: $captionsOn).toggleStyle(.button).controlSize(.small).help("Show the closed captions")
                    if asset.music != nil { AdverbBadge(text: "♪ beat-matched", color: .adverbGold) }
                }
                ZStack(alignment: .bottom) {
                    PlayerView(player: player.player)
                        .aspectRatio(orientation == .portrait ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: orientation == .portrait ? 560 : 260)
                        .clipShape(RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous))
                    if showPoster, let poster {
                        Button {
                            showPoster = false
                            player.player.play()
                        } label: {
                            ZStack {
                                Image(nsImage: poster).resizable().aspectRatio(contentMode: .fit)
                                Image(systemName: "play.circle.fill").font(.adverbGlyph(AdverbGlyph.display, weight: .light))
                                    .foregroundStyle(Color.adverbPearl).shadow(color: Color.adverbShadow, radius: 8)
                            }
                            .frame(maxWidth: .infinity, maxHeight: orientation == .portrait ? 560 : 260)
                            .clipShape(RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Play")
                    }
                    if !showPoster, captionsOn, let line = player.caption {
                        Text(line).adverbType(.labelStrong).foregroundStyle(Color.adverbPearl).multilineTextAlignment(.center)
                            .padding(.horizontal, .layer2).padding(.vertical, .layer1)
                            .background(Color.adverbInk.opacity(0.72), in: RoundedRectangle(cornerRadius: AdverbRadius.chip))
                            .padding(.bottom, .layer7)
                            .allowsHitTesting(false)
                    }
                }
                if let report = asset.render(orientation)?.report {
                    Text(report.line).adverbType(.codeSmall).foregroundStyle(report.isClean ? Color.adverbInkMuted : Color.adverbWarning)
                        .help(report.warnings.joined(separator: "\n"))
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: selection.orientation) { _, _ in load() }
        .onChange(of: asset.builtAt) { _, _ in load() }
        .onDisappear { player.stop() }
    }

    /// The first still (18 %): the headline is up and the visual has arrived.
    private var poster: NSImage? {
        asset.stills(orientation).min { $0.time < $1.time }.flatMap { ThumbnailCache.image(paths.url($0.path), maxPixels: 1400) }
    }

    private func load() {
        showPoster = true
        guard let render = asset.render(orientation) else { return }
        let captions = asset.a11y.captions(orientation).map { paths.url($0.vtt) }
        player.load(video: paths.url(render.path), captions: captions)
    }
}

/// An AVPlayer with the caption at its current time.
@MainActor
@Observable
final class CaptionedPlayer {
    let player = AVPlayer()
    var caption: String?
    private var cues: [Cue] = []
    private var observer: Any?
    private var loaded: URL?

    func load(video: URL, captions: URL?) {
        cues = captions.flatMap { try? String(contentsOf: $0, encoding: .utf8) }.map(WebVTTReader.parse) ?? []
        // A re-render keeps the file name: reload when the file changed.
        let item = AVPlayerItem(url: video)
        player.replaceCurrentItem(with: item)
        loaded = video
        caption = nil
        if observer == nil {
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] time in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let t = time.seconds
                    self.caption = self.cues.first { $0.start <= t && t < $0.end }?.text
                }
            }
        }
    }

    func stop() { player.pause() }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
