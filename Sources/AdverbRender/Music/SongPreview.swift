//
//  SongPreview.swift
//  AdverbRender
//
//  WHAT: Plays a song from an in-point for an asset's length and fades it out, so the person hears
//        what the cut will sound like before anything renders.
//

@preconcurrency import AVFoundation
import Foundation

@MainActor
public final class SongPreview {
    public static let shared = SongPreview()
    private var player: AVAudioPlayer?
    private var stopper: Task<Void, Never>?

    public private(set) var playingPath: String?
    public var currentTime: Double { player?.currentTime ?? 0 }
    public var isPlaying: Bool { player?.isPlaying ?? false }

    public init() {}

    public func play(_ url: URL, from inPoint: Double, for duration: Double, fadeOut: Double = 1.2, gainDB: Double = -3) {
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.currentTime = max(0, inPoint)
        player.volume = Float(pow(10, gainDB / 20))
        player.prepareToPlay()
        player.play()
        self.player = player
        playingPath = url.path
        stopper = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, duration - fadeOut) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            player.setVolume(0, fadeDuration: fadeOut)
            try? await Task.sleep(nanoseconds: UInt64(fadeOut * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    public func stop() {
        stopper?.cancel(); stopper = nil
        player?.stop(); player = nil
        playingPath = nil
    }
}
