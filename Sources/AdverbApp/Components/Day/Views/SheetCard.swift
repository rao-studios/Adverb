//
//  SheetCard.swift
//  Adverb
//
//  WHAT: A day's contact sheet, before its videos exist: the page at 18, 42, 66 and 97 % in both
//        orientations, as the writer made it on this Mac. Approve it (and render now, or with the
//        others), or send it back with a note: the page is changed to do what the note says and the
//        sheet drawn again. On a rendered day only the note is offered (the videos are above).
//  OUT:  approve, redo and render, to the caller (DayPane → AdverbRuntimeRoot)
//

import AdverbCore
import AdverbRuntime
import SwiftUI

struct SheetCard: View {
    let day: CampaignDay
    let asset: Asset
    let paths: CampaignPaths
    let busy: Bool
    /// The videos are made: no sheet image, only the note.
    var compact = false
    let approve: (_ renderNow: Bool) -> Void
    let redo: (_ note: String?) -> Void
    let render: () -> Void
    @State private var note = ""
    @State private var writingNote = false

    var body: some View {
        AdverbCard(gold: day.status == .sheeted && !compact) {
            VStack(alignment: .leading, spacing: .layer3) {
                HStack {
                    SectionLabel(compact ? "Change this day" : "Contact sheet")
                    Spacer()
                    if !compact { AdverbBadge(text: day.status.title, color: day.status == .approved ? .adverbGold : .adverbInkDim) }
                }
                if !compact, let sheet = asset.sheetPath {
                    if let image = ThumbnailCache.image(paths.url(sheet), maxPixels: 1_600) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous).strokeBorder(Color.adverbBorder))
                            .onTapGesture(count: 2) { NSWorkspace.shared.open(paths.url(sheet)) }
                            .help("Double-click to open the sheet full size")
                            .accessibilityLabel("Contact sheet: \(asset.a11y.altText)")
                    }
                    Text("Portrait on the left, landscape on the right, at 18, 42, 66 and 97 % of \(day.topic.duration) s\(asset.voiceOver != nil ? ", at the voice's pace" : "")\(asset.reviewed ? "; the writer looked at it and fixed what it saw" : "").")
                        .adverbType(.caption).foregroundStyle(Color.adverbInkDim)
                }
                if let asked = day.redoNote, !asked.isEmpty {
                    Text("Last asked: “\(asked)”").adverbType(.caption).foregroundStyle(Color.adverbInkSoft).textSelection(.enabled)
                }
                if !compact {
                    switch day.status {
                    case .sheeted:
                        HStack(spacing: .layer2) {
                            Button("Approve") { approve(false) }.buttonStyle(.adverbQuiet).disabled(busy)
                                .help("Right as it is: render it with the other approved days")
                            Button("Approve and render") { approve(true) }.buttonStyle(.adverbGold).disabled(busy)
                            Spacer()
                            Button(writingNote ? "Never mind" : "Send back…") { writingNote.toggle() }.buttonStyle(.adverbLink)
                        }
                    case .approved:
                        HStack(spacing: .layer2) {
                            if let at = day.approvedAt { Text("Approved \(at.formatted(date: .abbreviated, time: .shortened))").adverbType(.caption).foregroundStyle(Color.adverbInkDim) }
                            Spacer()
                            Button(writingNote ? "Never mind" : "Send back…") { writingNote.toggle() }.buttonStyle(.adverbLink)
                            Button("Render") { render() }.buttonStyle(.adverbGold).disabled(busy)
                        }
                    default:
                        EmptyView()
                    }
                }
                if writingNote || compact {
                    VStack(alignment: .leading, spacing: .layer2) {
                        AdverbTextArea(text: $note, minHeight: 54)
                        Text("Say what to change: “the code card runs off the right edge in portrait”, “a calmer headline”, “show the ⌃A panel sooner”. The page is changed to do it and the sheet drawn again; renders made from the old page are dropped.")
                            .adverbType(.fine).foregroundStyle(Color.adverbInkMuted)
                        HStack {
                            Button("Write it again from scratch") { writingNote = false; redo(nil) }.buttonStyle(.adverbLink).disabled(busy)
                            Spacer()
                            Button("Change the page") {
                                let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
                                note = ""; writingNote = false
                                redo(text.isEmpty ? nil : text)
                            }
                            .buttonStyle(.adverb).disabled(busy || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }
}
