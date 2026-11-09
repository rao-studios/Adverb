//
//  KokoroEngine+PublicAPI.swift
//  AdverbVoice (lifted from Ambient's AmbientVoice, 2026-11-08)
//
//  WHAT: speak / synthesizeChunk / synthesizeWaveform / synthesize.
//  IN:   KokoroEngine.swift (same actor)
//  OUT:  waveform → playback helpers
//

import Foundation
import AVFoundation
@preconcurrency import CoreML
import Accelerate

extension KokoroEngine {

    // MARK: - Public API

    /// Synthesize and play `text`. Neutral: player→mixer. Other styles: timePitch / EQ / reverb.
    public func speak(_ text: String, style: TTSSpeechStyle = .neutral) async throws {
        let waveform = try await synthesizeWaveform(text)
        if style.isNeutral {
            try await playSimple(waveform)
        } else {
            try await playStyled(waveform, style: style)
        }
    }

    /// Synthesize `text` and return raw float samples (post-DSP, ready for playback).
    public func synthesizeWaveform(_ text: String) async throws -> [Float] {
        try await synthesizeChunk(text).samples
    }

    /// One chunk with the engine's options: samples, their rate and the
    /// pronunciation trace, all from this call. Chunks render one at a time.
    public func synthesizeChunk(_ text: String) async throws -> SynthesizedChunk {
        try await synthesizeChunk(text, options: options)
    }

    /// One chunk with `options` — `.legacy` is the voice as it shipped.
    public func synthesizeChunk(_ text: String, options: KokoroOptions) async throws -> SynthesizedChunk {
        try Task.checkCancellation()
        return try await withGate { try await render(text, options: options) }
    }

    /// What the voice does around the model call from the next chunk on.
    public func setOptions(_ options: KokoroOptions) {
        self.options = options
    }

    /// Each chunk's synthesis report, for probes.
    package func setDiagnosticsHandler(_ handler: (@Sendable (KokoroSynthesisDiagnostics) -> Void)?) {
        onDiagnostics = handler
    }

    /// Synthesize to an AVAudioPCMBuffer at the model's native sample rate.
    public func synthesize(_ text: String) async throws -> AVAudioPCMBuffer {
        try pcmBuffer(from: try await synthesizeWaveform(text), sampleRate: sampleRate)
    }

}
