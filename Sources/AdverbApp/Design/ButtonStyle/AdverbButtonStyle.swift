//
//  AdverbButtonStyle.swift
//  Adverb
//
//  WHAT: Ink for the action a pane is asking for, gold for the one moment that matters (go live,
//        build the month), a quiet fill for the rest, red for the destructive.
//

import SwiftUI

struct AdverbButtonStyle: ButtonStyle {
    enum Kind { case prominent, gold, quiet, destructive }
    var kind: Kind = .prominent

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, kind: kind)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let kind: Kind
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .adverbType(.labelStrong)
                .lineLimit(1)
                .fixedSize()
                .padding(AdverbInset.control)
                .foregroundStyle(foreground)
                .background(RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous).fill(fill)
                    .opacity(configuration.isPressed ? 0.78 : 1))
                .overlay(RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous)
                    .strokeBorder(kind == .quiet ? Color.adverbBorder : Color.clear))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }

        private var foreground: Color {
            switch kind {
            case .prominent: return .adverbPearl
            case .gold: return .adverbOnGold
            case .quiet: return .adverbInk
            case .destructive: return .adverbError
            }
        }

        private var fill: AnyShapeStyle {
            switch kind {
            case .prominent: return AnyShapeStyle(hovering ? Color.adverbInk.opacity(0.85) : Color.adverbInk)
            case .gold: return AnyShapeStyle(Color.adverbFoil.opacity(hovering ? 0.9 : 1))
            case .quiet: return AnyShapeStyle(hovering ? Color.adverbFillHover : Color.adverbPearl)
            case .destructive: return AnyShapeStyle(Color.adverbError.opacity(hovering ? 0.18 : 0.1))
            }
        }
    }
}

struct AdverbLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Label(configuration: configuration) }

    private struct Label: View {
        let configuration: Configuration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .adverbType(.label)
                .foregroundStyle(Color.adverbGoldDeep)
                .underline(hovering)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == AdverbButtonStyle {
    static var adverb: AdverbButtonStyle { AdverbButtonStyle(kind: .prominent) }
    static var adverbGold: AdverbButtonStyle { AdverbButtonStyle(kind: .gold) }
    static var adverbQuiet: AdverbButtonStyle { AdverbButtonStyle(kind: .quiet) }
    static var adverbDestructive: AdverbButtonStyle { AdverbButtonStyle(kind: .destructive) }
}

extension ButtonStyle where Self == AdverbLinkButtonStyle {
    static var adverbLink: AdverbLinkButtonStyle { AdverbLinkButtonStyle() }
}
