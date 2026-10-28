//
//  RunsStrip.swift
//  Adverb
//
//  WHAT: The runs working on this campaign, along the window's foot: what each is doing, how far,
//        what Claude is thinking about, what it has cost, and Stop. Ended runs stay until cleared,
//        with why a failed one failed.
//

import AdverbAgents
import AdverbCore
import AdverbRuntime
import SwiftUI

struct RunsStrip: View {
    let runs: [RunProgress]
    let model: String
    @State private var expanded: String?

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.adverbBorder).frame(height: 1)
            HStack {
                SectionLabel("Runs")
                Text(summary).adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                Spacer()
                if runs.contains(where: { $0.phase != .running }) {
                    Button("Clear finished") { AdverbRuntimeRoot.shared.generation.set(.clearEnded) }.buttonStyle(.adverbLink)
                }
            }
            .padding(.horizontal, .layer4)
            .padding(.top, .layer2)
            ScrollView {
                VStack(spacing: .layer1) {
                    ForEach(runs) { run in row(run) }
                }
                .padding(.horizontal, .layer4)
                .padding(.bottom, .layer2)
            }
            // As tall as its rows, up to six; an open log gets the room.
            .frame(height: expanded == nil ? min(168, CGFloat(runs.count) * 26 + 10) : 168)
        }
        .background(Color.adverbPearlLow)
    }

    private var summary: String {
        let usage = runs.reduce(TokenUsage()) { $0 + $1.usage }
        let active = runs.filter { $0.phase == .running }.count
        var parts = ["\(active) running"]
        if !usage.isEmpty {
            parts.append("\((usage.input + usage.cacheRead + usage.cacheWrite).formatted()) in · \(usage.output.formatted()) out")
            parts.append(String(format: "%.0f%% from cache", usage.cacheHitRate * 100))
            parts.append(String(format: "≈ $%.2f", usage.estimatedUSD(model: model)))
        }
        let voice = runs.compactMap(\.voice).reduce(VoiceUsage()) { $0 + $1 }
        if !voice.isEmpty {
            parts.append(String(format: "%@ characters voiced ≈ $%.2f", voice.characters.formatted(), voice.estimatedUSD()))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func row(_ run: RunProgress) -> some View {
        VStack(alignment: .leading, spacing: .hairline) {
            HStack(spacing: .layer2) {
                StatusDot(color: color(run), pulsing: run.phase == .running)
                Text(title(run)).adverbType(.labelStrong).lineLimit(1)
                Text(run.step).adverbType(.caption).foregroundStyle(Color.adverbInkDim).lineLimit(1)
                if run.phase == .running { AdverbMeter(fraction: run.progress).frame(width: 90) }
                Spacer(minLength: .layer2)
                if !run.activity.isEmpty, run.phase == .running {
                    Text(lastLine(run.activity)).adverbType(.caption).foregroundStyle(Color.adverbInkMuted).lineLimit(1).truncationMode(.head)
                        .frame(maxWidth: 360, alignment: .trailing)
                }
                if let message = run.message, run.phase != .running {
                    Text(message).adverbType(.caption).foregroundStyle(run.phase == .failed ? Color.adverbError : Color.adverbInkDim)
                        .lineLimit(1).truncationMode(.tail).help(message).frame(maxWidth: 420, alignment: .trailing)
                }
                if run.phase == .running {
                    Button { AdverbRuntimeRoot.shared.cancelRun(run.key) } label: { Image(systemName: "stop.circle") }
                        .buttonStyle(.plain).foregroundStyle(Color.adverbInkDim).help("Stop")
                }
                Button { expanded = expanded == run.key ? nil : run.key } label: {
                    Image(systemName: expanded == run.key ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain).foregroundStyle(Color.adverbInkMuted).help("Log")
            }
            if expanded == run.key {
                Text(run.log.suffix(14).joined(separator: "\n")).adverbType(.codeSmall).foregroundStyle(Color.adverbInkDim)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.layer2)
                    .background(Color.adverbPearl, in: RoundedRectangle(cornerRadius: AdverbRadius.control))
            }
        }
        .padding(.vertical, .hairline)
    }

    private func title(_ run: RunProgress) -> String {
        switch run.kind {
        case "Plan": return "Plan"
        case "Beatmap": return "Day \(run.dayIndex ?? 0) · music"
        case "Voice": return "Day \(run.dayIndex ?? 0) · voice"
        default: return "Day \(run.dayIndex ?? 0)"
        }
    }

    private func color(_ run: RunProgress) -> Color {
        switch run.phase {
        case .running: .adverbGold
        case .finished: .adverbSuccess
        case .failed: .adverbError
        case .cancelled: .adverbInkMuted
        }
    }

    private func lastLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? s
    }
}
