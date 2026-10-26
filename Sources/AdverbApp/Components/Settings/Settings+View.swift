//
//  Settings+View.swift
//  Adverb
//

import AdverbCore
import AdverbRuntime
import SwiftUI

extension Settings {
    var view: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: .layer1) {
                Kicker(text: "Settings").padding(.bottom, .layer3)
                ForEach(SettingsSection.allCases) { section in
                    Button { navigation.section = section } label: {
                        Label(section.title, systemImage: section.symbol)
                            .adverbType(.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, .layer2).padding(.vertical, .snug)
                            .background(RoundedRectangle(cornerRadius: AdverbRadius.control, style: .continuous)
                                .fill(navigation.section == section ? Color.adverbFillSelected : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.layer4)
            .padding(.top, .layer5)
            .frame(width: AdverbLayout.settingsSidebar)
            .background(Color.adverbSidebar)
            Rectangle().fill(Color.adverbBorder).frame(width: 1)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: .layer4) {
                        VStack(alignment: .leading, spacing: .hairline) {
                            Headline(text: navigation.section.title, role: .pageTitle)
                            Text(navigation.section.subtitle).adverbType(.readingSmall).foregroundStyle(Color.adverbInkDim)
                        }
                        switch navigation.section {
                        case .general: GeneralPage(state: config.state)
                        case .claude: ClaudePage(state: config.state, keyDraft: $keyDraft)
                        case .rendering: RenderingPage(state: config.state)
                        case .about: AboutPage()
                        }
                    }
                    .frame(maxWidth: AdverbLayout.settingsMeasure, alignment: .leading)
                    .padding(.layer5)
                    .padding(.top, .layer4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let problem = config.state.problem {
                    NoticeBar(text: problem, tint: .adverbError) { AdverbRuntimeRoot.shared.config.set(.problem(nil)) }
                } else if let notice = config.state.notice {
                    NoticeBar(text: notice, tint: .adverbInkDim) { AdverbRuntimeRoot.shared.config.set(.notice(nil)) }
                }
            }
        }
        .onReceive(configChanged) { _ in tick &+= 1 }
    }
}
